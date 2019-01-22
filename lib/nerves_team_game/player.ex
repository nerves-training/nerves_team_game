defmodule NervesTeamGame.Player do
  @derive {Jason.Encoder, only: [:id, :ready, :tasks]}
  defstruct [
    id: nil,
    ready: false,
    tasks: [],
    pid: nil,
    monitor_ref: nil
  ]
end
