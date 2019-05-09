defmodule VintageNet.Technology.WiFi do
  @behaviour VintageNet.Technology

  alias VintageNet.WiFi.{Scan, WPA2}
  alias VintageNet.Interface.RawConfig

  @impl true
  def to_raw_config(ifname, %{type: __MODULE__, wifi: wifi_config} = config, opts) do
    ifup = Keyword.fetch!(opts, :bin_ifup)
    ifdown = Keyword.fetch!(opts, :bin_ifdown)
    wpa_supplicant = Keyword.fetch!(opts, :bin_wpa_supplicant)
    killall = Keyword.fetch!(opts, :bin_killall)
    tmpdir = Keyword.fetch!(opts, :tmpdir)
    regulatory_domain = Keyword.fetch!(opts, :regulatory_domain)

    network_interfaces_path = Path.join(tmpdir, "network_interfaces.#{ifname}")
    wpa_supplicant_conf_path = Path.join(tmpdir, "wpa_supplicant.conf.#{ifname}")
    control_interface_path = Path.join(tmpdir, "wpa_supplicant")

    hostname = config[:hostname] || get_hostname()

    files = [
      {network_interfaces_path, "iface #{ifname} inet dhcp" <> dhcp_options(hostname)},
      {wpa_supplicant_conf_path,
       wifi_to_supplicant_contents(wifi_config, control_interface_path, regulatory_domain)}
    ]

    up_cmds = [
      {:run, wpa_supplicant, ["-B", "-i", ifname, "-c", wpa_supplicant_conf_path, "-dd"]},
      {:run, ifup, ["-i", network_interfaces_path, ifname]}
    ]

    down_cmds = [
      {:run, ifdown, ["-i", network_interfaces_path, ifname]},
      {:run, killall, ["-q", "wpa_supplicant"]}
    ]

    {:ok,
     %RawConfig{
       ifname: ifname,
       type: __MODULE__,
       source_config: config,
       files: files,
       cleanup_files: [Path.join(control_interface_path, ifname)],
       child_specs: [{VintageNet.Interface.ConnectivityChecker, ifname}],
       up_cmds: up_cmds,
       down_cmds: down_cmds
     }}
  end

  def to_raw_config(ifname, %{type: __MODULE__}, opts) do
    wpa_supplicant = Keyword.fetch!(opts, :bin_wpa_supplicant)
    killall = Keyword.fetch!(opts, :bin_killall)
    tmpdir = Keyword.fetch!(opts, :tmpdir)

    wpa_supplicant_conf_path = Path.join(tmpdir, "wpa_supplicant.conf.#{ifname}")
    control_interface_path = Path.join(tmpdir, "wpa_supplicant")

    files = [
      {wpa_supplicant_conf_path, "ctrl_interface=#{control_interface_path}"}
    ]

    up_cmds = [
      {:run, wpa_supplicant, ["-B", "-i", ifname, "-c", wpa_supplicant_conf_path, "-dd"]}
    ]

    down_cmds = [
      {:run, killall, ["-q", "wpa_supplicant"]}
    ]

    {:ok,
     %RawConfig{
       ifname: ifname,
       type: __MODULE__,
       files: files,
       child_specs: [{VintageNet.Interface.ConnectivityChecker, ifname}],
       up_cmds: up_cmds,
       down_cmds: down_cmds,
       cleanup_files: [Path.join(control_interface_path, ifname)]
     }}
  end

  def to_raw_config(_ifname, _config, _opts) do
    {:error, :bad_configuration}
  end

  @impl true
  def ioctl(ifname, :scan, _args) do
    Scan.scan(ifname)
  end

  def ioctl(_ifname, _command, _args) do
    {:error, :unsupported}
  end

  defp wifi_to_supplicant_contents(wifi, control_interface_path, regulatory_domain) do
    [
      "ctrl_interface=#{control_interface_path}",
      "\n",
      "country=#{regulatory_domain}",
      "\n",
      into_wifi_network_config(wifi)
    ]
    |> IO.iodata_to_binary()
  end

  defp key_mgmt_to_string(key) when key in [:none, :wep], do: "NONE"
  defp key_mgmt_to_string(:wpa_psk), do: "WPA-PSK"
  defp key_mgmt_to_string(:wpa_eap), do: "WPA-EAP"

  defp into_wifi_network_config(%{networks: networks}) do
    Enum.map(networks, &into_wifi_network_config/1)
  end

  defp into_wifi_network_config(%{key_mgmt: :wep} = wifi) do
    network_config([
      into_config_string(wifi, :ssid),
      "key_mgmt=NONE",
      "wep_tx_keyidx=0",
      "wep_key0=#{wifi.psk}"
    ])
  end

  defp into_wifi_network_config(%{key_mgmt: :wpa_eap} = wifi) do
    network_config([
      into_config_string(wifi, :ssid),
      into_config_string(wifi, :key_mgmt),
      into_config_string(wifi, :scan_ssid),
      into_config_string(wifi, :priority),
      into_config_string(wifi, :pairwise),
      into_config_string(wifi, :group),
      into_config_string(wifi, :eap),
      into_config_string(wifi, :identity),
      into_config_string(wifi, :password),
      into_config_string(wifi, :phase1),
      into_config_string(wifi, :phase2)
    ])
  end

  defp into_wifi_network_config(wifi) do
    network_config([
      into_config_string(wifi, :ssid),
      into_config_string(wifi, :psk),
      into_config_string(wifi, :key_mgmt),
      into_config_string(wifi, :scan_ssid),
      into_config_string(wifi, :priority)
    ])
  end

  defp into_config_string(wifi, opt_key) do
    case Map.get(wifi, opt_key) do
      nil -> nil
      opt -> wifi_opt_to_config_string(wifi, opt_key, opt)
    end
  end

  defp wifi_opt_to_config_string(_wifi, :ssid, ssid) do
    "ssid=#{inspect(ssid)}"
  end

  defp wifi_opt_to_config_string(wifi, :psk, psk) do
    {:ok, real_psk} = WPA2.to_psk(wifi.ssid, psk)
    "psk=#{real_psk}"
  end

  defp wifi_opt_to_config_string(_wifi, :key_mgmt, key_mgmt) do
    "key_mgmt=#{key_mgmt_to_string(key_mgmt)}"
  end

  defp wifi_opt_to_config_string(_wifi, :scan_ssid, value) do
    "scan_ssid=#{value}"
  end

  defp wifi_opt_to_config_string(_wifi, :priority, value) do
    "priority=#{value}"
  end

  defp wifi_opt_to_config_string(_wifi, :identity, value) do
    "identity=#{value}"
  end

  defp wifi_opt_to_config_string(_wifi, :password, value) do
    "password=#{value}"
  end

  defp wifi_opt_to_config_string(_wifi, :phase1, value) do
    "phase1=#{value}"
  end

  defp wifi_opt_to_config_string(_wifi, :phase2, value) do
    "phase2=#{value}"
  end

  defp wifi_opt_to_config_string(_wifi, :pairwise, value) do
    "pairwise=#{value}"
  end

  defp wifi_opt_to_config_string(_wifi, :group, value) do
    "group=#{value}"
  end

  defp wifi_opt_to_config_string(_wifi, :eap, value) do
    "eap=#{value}"
  end

  # TODO: Remove duplication with ethernet!!
  defp dhcp_options(hostname) do
    """

      script #{udhcpc_handler_path()}
      hostname #{hostname}
    """
  end

  defp udhcpc_handler_path() do
    Application.app_dir(:vintage_net, ["priv", "udhcpc_handler"])
  end

  defp get_hostname do
    {:ok, hostname} = :inet.gethostname()
    to_string(hostname)
  end

  defp network_config(config) do
    config =
      Enum.map(config, fn
        nil -> []
        conf -> [conf, "\n"]
      end)

    ["network={", "\n", config, "}", "\n"]
  end
end
