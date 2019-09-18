defmodule VintageNet.Interface.RawConfig do
  @moduledoc """
  Raw configuration for an interface

  This struct contains the low-level instructions for how to configure and
  unconfigure an interface.

  Fields:

  * `ifname` - the name of the interface (e.g., `"eth0"`)
  * `type` - the type of network interface (aka the module that created the config)
  * `source_config` - the configuration that generated this one
  * `require_interface` - require the interface to exist in the system before configuring
  * `retry_millis` - if bringing the interface up fails, wait this amount of time before retrying
  * `files` - a list of file path, content tuples
  * `restart_strategy` - the restart strategy for the list of `child_specs`. I.e., `:one_for_one | :one_for_all | :rest_for_one
  * `child_specs` - a set of child_specs for GenServers to start up and supervise
  * `up_cmd_millis` - the maximum amount of time to allow the up command list to take
  * `up_cmds` - a list of commands to run to configure the interface
  * `down_cmd_millis` - the maximum amount of time to allow the down command list to take
  * `down_cmds` - a list of commands to run to unconfigure the interface
  * `cleanup_files` - additional files to delete (the files listed in `files` are deleted too)

  """

  # Should this just be a function??? The down side is that it's less testable since functions are opaque.
  @type command :: {:run | :run_ignore_errors, String.t(), [String.t()]} | {:fun, function()}
  @type file_contents :: {Path.t(), String.t()}

  @enforce_keys [:ifname, :type, :source_config]
  defstruct ifname: nil,
            type: nil,
            source_config: %{},
            require_interface: true,
            retry_millis: 30_000,
            files: [],
            restart_strategy: :one_for_all,
            child_specs: [],
            up_cmd_millis: 5_000,
            up_cmds: [],
            down_cmd_millis: 5_000,
            down_cmds: [],
            cleanup_files: []

  @type t :: %__MODULE__{
          ifname: VintageNet.ifname(),
          type: atom(),
          source_config: map(),
          require_interface: boolean(),
          retry_millis: non_neg_integer(),
          files: [file_contents()],
          restart_strategy: Supervisor.strategy(),
          child_specs: [Supervisor.child_spec() | {module(), term()} | module()],
          up_cmd_millis: non_neg_integer(),
          up_cmds: [command()],
          down_cmd_millis: non_neg_integer(),
          down_cmds: [command()],
          cleanup_files: [Path.t()]
        }

  def unimplemented_ioctl(_, _), do: {:error, :unimplemented}
end
