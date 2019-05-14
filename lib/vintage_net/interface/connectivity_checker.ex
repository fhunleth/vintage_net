defmodule VintageNet.Interface.ConnectivityChecker do
  use GenServer

  alias VintageNet.{PropertyTable, RouteManager}

  require Record

  @delay_to_first_check 100
  @interval 30_000
  @ping_port 80

  @doc false
  Record.defrecord(:hostent, Record.extract(:hostent, from_lib: "kernel/include/inet.hrl"))

  @doc """
  Start the connectivity checker GenServer
  """
  @spec start_link(VintageNet.ifname()) :: GenServer.on_start()
  def start_link(ifname) do
    GenServer.start_link(__MODULE__, ifname)
  end

  @impl true
  def init(ifname) do
    ping_wait(@delay_to_first_check)
    {:ok, %{ifname: ifname, interval: @interval}}
  end

  @impl true
  def handle_info(:ping, %{ifname: ifname, interval: interval} = state) do
    connectivity =
      case ping(ifname) do
        :ok ->
          :internet

        {:error, :if_not_found} ->
          :disconnected

        {:error, :no_ipv4_address} ->
          :disconnected

        {:error, _reason} ->
          :lan
      end

    set_connectivity(ifname, connectivity)
    ping_wait(interval)
    {:noreply, state}
  end

  defp ping(ifname) do
    internet_host = Application.get_env(:vintage_net, :internet_host)

    with {:ok, src_ip} <- get_interface_address(ifname),
         {:ok, dest_ip} <- resolve_addr(internet_host),
         {:ok, tcp} <- :gen_tcp.connect(dest_ip, @ping_port, ip: src_ip) do
      _ = :gen_tcp.close(tcp)
      :ok
    end
  end

  defp get_interface_address(ifname) do
    with {:ok, addresses} <- :inet.getifaddrs(),
         {:ok, params} <- find_ifaddr(addresses, ifname) do
      find_ipv4_addr(params)
    end
  end

  defp find_ifaddr(addresses, ifname) do
    ifname_cl = to_charlist(ifname)

    case Enum.find(addresses, fn {k, _v} -> k == ifname_cl end) do
      {^ifname_cl, params} -> {:ok, params}
      _ -> {:error, :if_not_found}
    end
  end

  defp find_ipv4_addr(params) do
    case Enum.find(params, &ipv4_addr?/1) do
      {:addr, ipv4_addr} -> {:ok, ipv4_addr}
      _ -> {:error, :no_ipv4_address}
    end
  end

  defp ipv4_addr?({:addr, {_, _, _, _}}), do: true
  defp ipv4_addr?(_), do: false

  # Note: No support for DNS since DNS can't be forced through
  # an interface. I.e., errors on other interfaces mess up DNS
  # even if the one of interest is ok.
  defp resolve_addr(address) when is_tuple(address) do
    {:ok, address}
  end

  defp ping_wait(interval) do
    Process.send_after(self(), :ping, interval)
  end

  defp set_connectivity(ifname, connectivity) do
    RouteManager.set_connection_status(ifname, connectivity)
    PropertyTable.put(VintageNet, ["interface", ifname, "connection"], connectivity)
  end
end
