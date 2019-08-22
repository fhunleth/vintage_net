defmodule VintageNet.Technology.Ethernet do
  @behaviour VintageNet.Technology

  alias VintageNet.Interface.RawConfig
  alias VintageNet.IP.ConfigToInterfaces

  @impl true
  def normalize(%{type: __MODULE__} = config), do: {:ok, config}

  @impl true
  def to_raw_config(ifname, %{type: __MODULE__} = config, opts) do
    ifup = Keyword.fetch!(opts, :bin_ifup)
    ifdown = Keyword.fetch!(opts, :bin_ifdown)
    tmpdir = Keyword.fetch!(opts, :tmpdir)

    network_interfaces_path = Path.join(tmpdir, "network_interfaces.#{ifname}")

    {:ok,
     %RawConfig{
       ifname: ifname,
       type: __MODULE__,
       source_config: config,
       files: [
         {network_interfaces_path,
          ConfigToInterfaces.config_to_interfaces_contents(ifname, config)}
       ],
       child_specs: [{VintageNet.Interface.InternetConnectivityChecker, ifname}],
       # ifup hangs forever until Ethernet is plugged in
       up_cmd_millis: 60_000,
       up_cmds: [
         {:run_ignore_errors, ifdown, ["-i", network_interfaces_path, ifname]},
         {:run, ifup, ["-i", network_interfaces_path, ifname]}
       ],
       down_cmd_millis: 5_000,
       down_cmds: [{:run, ifdown, ["-i", network_interfaces_path, ifname]}]
     }}
  end

  def to_raw_config(_ifname, _config, _opts) do
    {:error, :bad_configuration}
  end

  @impl true
  def ioctl(_ifname, _command, _args) do
    {:error, :unsupported}
  end

  @impl true
  def check_system(opts) do
    # TODO
    with :ok <- check_program(opts[:bin_ifup]) do
      :ok
    end
  end

  defp check_program(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, "Can't find #{path}"}
    end
  end
end
