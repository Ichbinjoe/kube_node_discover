# Copyright (c) 2017 Joseph Sacchini
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the 2nd version of the GNU General
# Public License as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

defmodule KubeNodeDiscover.Worker do
  use GenServer
  require Logger

  alias KubeNodeDiscover.Discover

  @tick_rate 3000

  def start_link do
    init_state = %{ever_seen_node: false, notify_targets: MapSet.new()}
    GenServer.start_link(__MODULE__, init_state, name: __MODULE__)
  end

  def init(state) do
    if !Node.alive? do
      warn("the local node is not alive, will not search for cluster")
      :ignore
    else
      {:noreply, state} = handle_info(:update, state)
      info("init clustering controller for node: #{Node.self()}")
      {:ok, state}
    end
  end

  defp schedule_tick do
    Process.send_after(self(), :update, @tick_rate)
  end

  def handle_call(:wait_ready, from, state) do
    if state.ever_seen_node do
      {:reply, :ok, state}
    else
      notify_targets =
        state.notify_targets
        |> MapSet.put(from)

      warn("making #{from} wait while we find nodes")
      state = %{state | notify_targets: notify_targets}
      {:noreply, state}
    end
  end

  def handle_info(:update, state) do
    connect_to = Discover.get_kube_nodes(selector())
    already_connected = MapSet.new(Node.list())

    connections =
      MapSet.difference(connect_to, already_connected)
      |> Enum.map(& {&1, Node.connect(&1)})

    ok_count = log(connections, true, & "new connection to #{&1}")
    log(connections, false, & "failed to connect to #{&1}", &warn/1)

    notify_targets = state.notify_targets
    state =
      if ok_count > 0 && !state.ever_seen_node do
        count =
          notify_targets
          |> MapSet.to_list()
          |> notify_ready()

        info("notified #{count} processes that we are ready")
        %{ever_seen_node: true, notify_targets: []}
      else
        state
      end

    disconnections =
      MapSet.difference(already_connected, connect_to)
      |> Enum.map(& {&1, Node.disconnect(&1)})

    log(disconnections, true, & "disconnected from dead node #{&1}")
    log(disconnections, false, & "failed to disconnect from dead node #{&1}", &warn/1)

    schedule_tick()
    {:noreply, state}
  end

  defp selector() do
    Application.get_env(:kube_node_discover, :selector)
  end

  defp notify_ready([]), do: 0
  defp notify_ready([target | targets]) do
    GenServer.reply(target, :ok)
    1 + notify_ready(targets)
  end

  defp log(nodes, status, formatter, logger \\ &info/1)
  defp log([], _, _, _), do: 0
  defp log([conn | rest], status, formatter, logger) do
    log(conn, status, formatter, logger) + log(rest, status, formatter, logger)
  end
  defp log({node, status}, target_status, formatter, logger) do
    if status == target_status do
      logger.(formatter.(node))
      1
    else
      0
    end
  end

  @logging_prefix "[cluster]"
  defp info(msg, prefix \\ @logging_prefix), do: do_logging(msg, prefix, &Logger.info/1)
  defp warn(msg, prefix \\ @logging_prefix), do: do_logging(msg, prefix, &Logger.warn/1)
  defp do_logging(msg, prefix, to) do
    to.("#{prefix} #{msg}")
  end
end