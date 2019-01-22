defmodule NervesTeamGame.GameSupervisor do
  use DynamicSupervisor

  alias NervesTeamGame.Game

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def game_start(id, opts) do
    spec = {Game, {id, opts}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def game_end(id) do
    name = Game.name(id)
    if pid = Process.whereis(name) do
      DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @impl true
  def init(opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
