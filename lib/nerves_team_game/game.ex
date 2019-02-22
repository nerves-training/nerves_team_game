defmodule NervesTeamGame.Game do
  @moduledoc """
  Game Server Messages

  Player messages

    {"actions:assigned", [%NervesTeamGame.Game.Task.Action{}, ...]}
    {"task:assigned", %NervesTeamGame.Game.Task{}}

  Global messages

    {"game:prepare", %{duration: 1000}}
    {"game:starting", %{duration: 2000}}
    {"game:start", %{}}
    {"game:progress", %{percent: 0..100}}
    {"game:ended", %{win?: true/false}}

  """
  use GenServer

  alias NervesTeamGame.Game.Task
  require Logger

  # Three minutes
  @game_milliseconds 1_000 * 60 * 3
  @game_score_win 100
  @game_score_start 50
  @game_score_min 0
  @game_score_max 100

  @task_points 5

  def child_spec({id, opts}) do
    %{
      id: name(id),
      start: {__MODULE__, :start_link, [id, opts]},
      restart: :temporary
    }
  end

  @doc """
  Start a new game server.

  It is required that the players required to start the game be passed in the opts

    players: [%NervesTeamGame.Player{}, ...]
  """
  def start_link(id, opts \\ []) do
    GenServer.start_link(__MODULE__, {id, opts}, name: name(id))
  end

  @doc """
  Create a unique name for the game server process
  """
  def name(id) do
    Module.concat(__MODULE__, to_string(id))
  end

  @doc """
  Join a player to the game server.

  Once all players have joined, each player will receive the following messages
  in order until the game has started

    {"game:prepare", %{duration: 1000}}
    {"game:starting", %{duration: 2000}}
    {"game:start", %{}}

  """
  def player_join(game_id, player_id, player_pid \\ nil) do
    player_pid = player_pid || self()
    GenServer.call(name(game_id), {:player_join, player_id, player_pid})
  end

  @doc """
  Execute an action in the game.

  Players are assigned one task and two actions. An action corresponds to an
  assigned task. If the action completes an open task, the player who was assigned
  the task will be sent the message

    {"task:assigned", %NervesTeamGame.Game.Task{}}
  """
  def action_execute(game_id, action) do
    GenServer.cast(name(game_id), {:action_execute, action})
  end

  @impl true
  def init({id, opts}) do
    {:ok,
     %{
       id: id,
       waiting_players: opts[:players],
       players: %{},
       tasks: [],
       actions: [],
       score: @game_score_start,
       min: @game_score_min,
       max: @game_score_max,
       timer_ref: nil
     }}
  end

  @impl true
  def handle_call({:player_join, player_id, player_pid}, _from, s) do
    _ = Logger.debug("Game #{s.id} | Player joined: #{player_id}")
    {%{^player_id => player}, waiting_players} = Map.split(s.waiting_players, [player_id])
    monitor_ref = Process.monitor(player_pid)

    player =
      player
      |> Map.put(:pid, player_pid)
      |> Map.put(:monitor_ref, monitor_ref)

    players = Map.put(s.players, player_id, player)

    if waiting_players == %{} do
      Process.send_after(self(), :game_prepare, 1_000)
    end

    {:reply, {:ok, player}, %{s | players: players, waiting_players: waiting_players}}
  end

  @impl true
  def handle_cast({:action_execute, %{"id" => action_id}}, %{players: players, tasks: tasks} = s) do
    action_id = String.to_atom(action_id)

    s =
      case Enum.find(tasks, &(&1.id == action_id && &1.player_id != nil)) do
        nil ->
          s

        task ->
          if ref = task.timer_ref do
            Process.cancel_timer(ref)
          end

          player = Map.get(players, task.player_id)
          assign_task(player)

          score = s.score + @task_points
          task = %{task | player_id: nil, timer_ref: nil}
          {_, tasks} = Enum.split_with(tasks, &(&1.id == task.id))
          broadcast(players, "game:progress", %{percent: (s.score - s.min) / (s.max - s.min)})
          %{s | tasks: [task | tasks], score: score}
      end

    maybe_game_over(s)
    {:noreply, s}
  end

  @impl true
  def handle_info(:game_prepare, %{players: players} = s) do
    delay = 2000
    broadcast(players, "game:prepare", %{duration: delay})

    players = Map.values(players)
    player_count = Enum.count(players)

    tasks = Enum.take_random(Task.all(), player_count * 2)

    actions =
      tasks
      |> Enum.map(& &1.action)
      |> Enum.shuffle()
      |> Enum.chunk_every(2)

    actions =
      Enum.zip(players, actions)
      |> Enum.reduce([], fn {player, actions}, assigned ->
        player_actions = Enum.map(actions, &Map.put(&1, :player_id, player.id))
        send(player.pid, {"actions:assigned", %{actions: player_actions}})
        player_actions ++ assigned
      end)

    assigned_tasks =
      Enum.zip(players, tasks)
      |> Enum.reduce([], fn {player, task}, assigned ->
        player_task = %{task | player_id: player.id}
        [player_task | assigned]
      end)

    assigned_task_ids = Enum.map(assigned_tasks, & &1.id)

    unassigned_tasks = Enum.reject(tasks, &(&1.id in assigned_task_ids))

    Process.send_after(self(), :game_starting, delay)
    {:noreply, %{s | tasks: assigned_tasks ++ unassigned_tasks, actions: actions}}
  end

  @impl true
  def handle_info(:game_starting, s) do
    delay = 1000
    broadcast(s.players, "game:starting", %{duration: delay})
    Process.send_after(self(), :game_start, delay)
    {:noreply, s}
  end

  @impl true
  def handle_info(:game_start, %{tasks: tasks} = s) do
    broadcast(s.players, "game:start", %{})

    {assigned_tasks, unassigned_tasks} = Enum.split_with(tasks, &(&1.player_id != nil))

    # Start timer on all assigned tasks
    assigned_tasks =
      Enum.map(assigned_tasks, fn task ->
        player = Map.get(s.players, task.player_id)
        send(player.pid, {"task:assigned", task})
        timer_ref = Process.send_after(self(), {:task_expired, task}, task.expire)
        %{task | timer_ref: timer_ref}
      end)

    # Start the death clock
    interval = trunc(@game_milliseconds / @game_score_win)

    {:ok, _timer_ref} = :timer.send_interval(interval, :game_tick)

    {:noreply, %{s | tasks: assigned_tasks ++ unassigned_tasks}}
  end

  @impl true
  def handle_info(:game_tick, %{max: max, min: min, score: score} = s) do
    min = min + 1
    broadcast(s.players, "game:progress", %{percent: score / (max - min)})
    {:noreply, %{s | min: min}}
  end

  @impl true
  def handle_info({:assign_task, player}, %{tasks: tasks} = s) do
    task =
      tasks
      |> Enum.filter(&(&1.player_id == nil))
      |> Enum.shuffle()
      |> List.first()
      |> Map.put(:player_id, player.id)

    timer_ref = Process.send_after(self(), {:task_expired, task}, task.expire)
    task = Map.put(task, :timer_ref, timer_ref)

    send(player.pid, {"task:assigned", task})
    {_, tasks} = Enum.split_with(tasks, &(&1.id == task.id))

    {:noreply, %{s | tasks: [task | tasks]}}
  end

  @impl true
  def handle_info({:task_expired, task}, %{players: players, tasks: tasks} = s) do
    player = Map.get(players, task.player_id)
    score = s.score - @task_points

    task = %{task | player_id: nil, timer_ref: nil}
    {_, tasks} = Enum.split_with(tasks, &(&1.id == task.id))

    s = %{s | score: score, tasks: tasks}

    maybe_game_over(s)
    assign_task(player)

    {:noreply, %{s | tasks: [task | tasks]}}
  end

  @impl true
  def handle_info(:stop, s) do
    {:stop, :normal, s}
  end

  @impl true
  def handle_info({:DOWN, _monitor_ref, :process, _pid, _reason}, s) do
    game_over(s.players, false)
    {:noreply, s}
  end

  defp maybe_game_over(s) do
    cond do
      s.score >= s.max -> game_over(s.players, true)
      s.score <= s.min -> game_over(s.players, false)
      true -> :noop
    end
  end

  defp game_over(players, win?) do
    broadcast(players, "game:ended", %{win?: win?})
    Process.exit(self(), :normal)
  end

  defp assign_task(player) do
    send(self(), {:assign_task, player})
  end

  defp broadcast(players, event, payload) do
    Enum.each(players, &(elem(&1, 1).pid |> send({event, payload})))
  end
end
