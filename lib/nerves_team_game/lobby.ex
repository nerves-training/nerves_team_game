defmodule NervesTeamGame.Lobby do
  @moduledoc """
  Lobby Server Messages

  Player messages

    {"player:assigned", %NervesTeamGame.Player{}}
    {"game:start", %{game_id: "", player_id: ""}}

  Global messages

    {"player:joined", %NervesTeamGame.Player{}}
    {"player:left", %NervesTeamGame.Player{}}
    {"player:list", [%NervesTeamGame.Player{}, ...]}
    {"game:pending", %{duration: 1000}}
    {"game:wait", %{}}
  """
  use GenServer

  alias NervesTeamGame.{GameSupervisor, Player}

  @ids "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890" |> String.graphemes()
  @start_delay 2_000

  @doc """
  Start the lobby server
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add a new player to the lobby. New players will be assigned a unique capital
  letter.

  The lobby server will monitor the pid of the caller and send messages in the
  form of `{event, payload}`.

  Once a unique id has been created, the player will be sent the message

    {"player:assigned", %NervesTeamGame.Player{}}
  """
  def add_player(pid \\ nil) do
    pid = pid || self()
    GenServer.call(__MODULE__, {:add_player, pid})
  end

  @doc """
  Remove a player from the lobby
  """
  def remove_player(id) do
    GenServer.call(__MODULE__, {:remove_player, id})
  end

  @doc """
  Designate that the player may be ready to play a game.

  If more then one player sets ready to true, the lobby will start a 2 second timer.
  Upon expiration of the timer, if the number of players ready is greater than one,
  the lobby will send all ready players a message:

    {"game:start", %{game_id: "1234", player_id: "Z"}}

  Upon receiving this message, the client should join the topic `game:1234` with
  the join params `%{player_id: "Z"}`.

  Players who were not ready at the time a game begins will remain in the lobby.
  """
  def ready_player(id, ready?) do
    GenServer.call(__MODULE__, {:ready_player, id, ready?})
  end

  @doc """
  Return a list of all players in the lobby
  """
  def players() do
    GenServer.call(__MODULE__, :players)
  end

  @impl true
  def init(_opts) do
    {:ok,
     %{
       timer_ref: nil,
       players: %{}
     }}
  end

  @impl true
  def handle_call({:add_player, pid}, _from, %{players: players} = s) do
    ids = Enum.map(players, &elem(&1, 1).id)
    id = Enum.uniq(@ids -- ids) |> Enum.random()

    monitor_ref = Process.monitor(pid)
    player = %Player{id: id, pid: pid, monitor_ref: monitor_ref}

    send(player.pid, {"player:assigned", player})
    broadcast(players, "player:joined", player)

    players = Map.put(players, id, player)

    broadcast(players, "player:list", %{players: Map.values(players)})
    {:reply, {:ok, player}, %{s | players: players}}
  end

  @impl true
  def handle_call({:ready_player, id, ready?}, _from, %{players: players} = s) do
    case Map.get(players, id) do
      nil ->
        {:reply, :error, s}

      player ->
        player = Map.put(player, :ready, ready?)
        players = Map.put(players, id, player)
        broadcast(players, "player:ready", player)
        ready = Enum.filter(players, &(elem(&1, 1).ready == true))
        ready_count = Enum.count(ready)
        s = %{s | players: players}

        s =
          if ready_count > 1 do
            timer_ref = Process.send_after(self(), :game_start, @start_delay)
            broadcast(players, "game:pending", %{duration: @start_delay})
            %{s | timer_ref: timer_ref}
          else
            broadcast(players, "game:wait", %{})

            if timer_ref = s.timer_ref do
              Process.cancel_timer(timer_ref)
            end

            %{s | timer_ref: nil}
          end

        {:reply, {:ok, player}, s}
    end
  end

  @impl true
  def handle_call(:players, _from, s) do
    {:reply, Map.values(s.players), s}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, %{players: players} = s) do
    {id, _} = Enum.find(players, &(elem(&1, 1).monitor_ref == monitor_ref))
    {%{^id => player}, players} = Map.split(players, [id])
    broadcast(players, "player:left", player)
    broadcast(players, "player:list", %{players: Map.values(players)})
    {:noreply, %{s | players: players}}
  end

  @impl true
  def handle_info(:game_start, s) do
    ready_ids =
      Enum.filter(s.players, &(elem(&1, 1).ready == true))
      |> Enum.map(&elem(&1, 1).id)

    ready = Map.take(s.players, ready_ids)
    ready_count = Enum.count(ready)

    if ready_count > 1 do
      game_id = System.unique_integer([:positive]) |> to_string()
      {:ok, _pid} = GameSupervisor.game_start(game_id, players: ready)

      Enum.each(
        ready,
        &(elem(&1, 1).pid |> send({"game:start", %{game_id: game_id, player_id: elem(&1, 1).id}}))
      )
    end

    {:noreply, s}
  end

  defp broadcast(players, event, payload) do
    Enum.each(players, &(elem(&1, 1).pid |> send({event, payload})))
  end
end
