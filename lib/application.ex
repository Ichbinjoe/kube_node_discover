defmodule KubeNodeDiscover do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      worker(KubeNodeDiscover.Worker, [])
    ]

    opts = [strategy: :one_for_one, name: KubeNodeDiscover.Supervisor]
    Supervisor.start_link(children, opts)
  end
end