defmodule NervesTeamGame.Game.Task do
  alias __MODULE__

  defmodule Action do
    @derive {Jason.Encoder, only: [:id, :title]}
    defstruct id: nil,
              title: nil,
              player_id: nil
  end

  @expire 5_000

  @derive {Jason.Encoder, only: [:id, :title, :expire]}
  defstruct id: nil,
            player_id: nil,
            title: nil,
            action: nil,
            timer_ref: nil,
            expire: @expire

  @all [
    {:nerves_time, "1970-01-01", "nerves\ntime"},
    {:mix_firmware, "Build\nfirmware", "mix\nfirmware"},
    {:mix_deps_get, "Fetch\ndeps", "mix\ndeps.get"},
    {:git_rebase, "Merge\nconflict", "git\nrebase"},
    {:empty_list, "Empty\nlist", "[ ]"},
    {:empty_map, "Empty\nmap", "%{ }"},
    {:mix_compile, "Compile", "mix\ncompile"},
    {:mix_burn, "Burn\nSD", "mix\nburn"},
    {:mix_clean, "Clean\nProj", "mix\nclean"},
    {:nerves_hub, "NervesHub", "nerves\nhub"},
    {:exception, "Exception", "rescue"},
    {:format, "Unformatted\ncode", "mix\nformat"},
    {:typespec, "typespec\nerror", "mix\ndialyzer"},
    {:new_proj, "New\nproject", "mix\nnew"}
  ]

  def all do
    Enum.reduce(@all, [], fn {id, task_title, action_title}, acc ->
      task = %Task{
        id: id,
        title: task_title,
        action: %Task.Action{id: id, title: action_title}
      }

      [task | acc]
    end)
  end
end
