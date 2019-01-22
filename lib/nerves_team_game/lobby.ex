defmodule NervesTeamGame.Lobby do
  use GenServer

  alias NervesTeamGame.{GameSupervisor, Player}

  @ids "ABCDEFGHIJKLMNOPQRSTUVWXYZ" |> String.graphemes()
  @start_delay 2_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def add_player(pid \\ nil) do
    pid = pid || self()
    GenServer.call(__MODULE__, {:add_player, pid})
  end

  def remove_player(id) do
    GenServer.call(__MODULE__, {:remove_player, id})
  end

  def ready_player(id, ready?) do
    GenServer.call(__MODULE__, {:ready_player, id, ready?})
  end

  def players() do
    GenServer.call(__MODULE__, :players)
  end

  @impl true
  def init(_opts) do
    {:ok, %{
      timer_ref: nil,
      players: %{}
    }}
  end

  @impl true
  def handle_call({:add_player, pid}, _from, %{players: players} = s) do
    ids = Enum.map(players, &elem(&1, 1).id)
    id = Enum.uniq(@ids -- ids) |> Enum.random

    monitor_ref = Process.monitor(pid)
    player = %Player{id: id, pid: pid, monitor_ref: monitor_ref}

    {:reply, {:ok, player}, %{s | players: Map.put(players, id, player)}}
  end

  @impl true
  def handle_call({:ready_player, id, ready?}, _from, %{players: players} = s) do
    case Map.get(players, id) do
      nil ->
        {:reply, :error, s}

      player ->
        player = Map.put(player, :ready, ready?)
        players = Map.put(players, id, player)

        ready = Enum.filter(players, &elem(&1, 1).ready == true)
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
    {id, _} = Enum.find(players, &elem(&1, 1).monitor_ref == monitor_ref)
    {%{^id => player}, players} = Map.split(players, [id])
    broadcast(players, "player:left", player)
    {:noreply, %{s | players: players}}
  end

  @impl true
  def handle_info(:game_start, s) do
    ready_ids =
      Enum.filter(s.players, &elem(&1, 1).ready == true)
      |> Enum.map(&elem(&1, 1).id)
    ready = Map.take(s.players, ready_ids)
    ready_count = Enum.count(ready)
    if ready_count > 1 do
      game_id = System.unique_integer([:positive])
      GameSupervisor.game_start(game_id, players: ready)
      Enum.each(ready, &elem(&1, 1).pid |> send({"game:start", %{id: game_id}}))
    end
    {:noreply, s}
  end

  defp broadcast(players, event, payload) do
    Enum.each(players, &elem(&1, 1).pid |> send({event, payload}))
  end
end
