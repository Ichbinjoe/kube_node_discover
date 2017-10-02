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

defmodule KubeNodeDiscover.Discover do
  @kubernetes_master "kubernetes.default.svc"
  @service_account_path "/var/run/secrets/kubernetes.io/serviceaccount"

  def get_kube_nodes(selector, url \\ @kubernetes_master) do
    path = "api/v1/namespaces/#{namespace()}/pods?labelSelector=#{selector}"
    headers = [{'authorization', 'Bearer #{token()}'}]
    http_options = [ssl: [verify: :verify_none]]
    request = {'https://#{url}/#{path}', headers}

    response =
      :httpc.request(:get, request, http_options, [])
      |> handle_httpc_return_value()

    case response do
      {:ok, resp} ->
        resp
        |> decode()
        |> parse_response()
      {:error, err} when is_list(err) ->
        raise List.to_string(err)
    end
    |> Enum.filter(&pod_healthy?/1)
    |> Enum.map(&pod_details/1)
    |> Enum.map(fn {name, ip} -> :"#{name}@#{ip}" end)
    |> Enum.reject(& &1 == node())
    |> MapSet.new()
  end

  defp handle_httpc_return_value({:ok, resp}), do: handle_httpc_resp_value(resp)
  defp handle_httpc_return_value({:error, err}), do: {:error, [httpc: err]}

  defp handle_httpc_resp_value({{_, status, _}, _, body}), do: handle_httpc_status(status, body)

  defp handle_httpc_status(200, body), do: {:ok, body}
  defp handle_httpc_status(403, body), do: {:error, [unauthorized: decode(body)["message"]]}
  defp handle_httpc_status(status, body), do: {:error, [bad_status: status, body: body]}

  defp token(), do: read_param_file("token")
  defp namespace(), do: read_param_file("namespace")

  defp read_param_file(name) do
    path = Path.join(@service_account_path, name)
    if File.exists?(path) do
      path
      |> File.read!()
      |> String.trim()
    else
      raise "could not find kubernetes param '#{name}'"
    end
  end

  defp decode(body), do: Poison.decode!(body)

  defp parse_response(%{"kind" => "PodList", "items" => items}) when is_list(items),
       do: items

  defp pod_healthy?(%{"status" => %{"phase" => "Running", "containerStatuses" => containers}}) do
    count_any = length(containers)

    count_healthy =
      containers
      |> Enum.filter(& container_healthy?/1)
      |> length()

    count_healthy == count_any
  end
  defp pod_healthy?(_), do: false

  defp container_healthy?(%{"state" => %{"running" => _}, "ready" => true}), do: true
  defp container_healthy?(_), do: false

  defp pod_details(%{"status" => %{"podIP" => ip}, "metadata" => %{"name" => name}}),
       do: {name, ip}
end
