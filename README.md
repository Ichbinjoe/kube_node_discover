# KubeNodeDiscover

I've tried to use bitwalker's [libcluster](https://github.com/bitwalker/libcluster), but found it a bit overkill for my very
simple use case. This uses the most straightforward API calls to kubernetes, and lets you configure
using a pod selector directly.

This library watches kubernetes and automatically tries to connect to nodes it finds on in the same
namespace that match the selector specified in the config.

## Installation

The package can be installed
by adding `kube_node_discover` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:kube_node_discover, "~> 0.1.0"}]
end
```

## Configuration

To specify a pod selector, use the following configuration:

```elixir
config :kube_node_discover,
  selector: "app=my-app"
```

## Process

The library uses the following process to do it's discovery:

* Figure out which namespace I am in, by reading the file `/var/run/secrets/kubernetes.io/serviceaccount/namespace`
* Read the authentication token from the mounted service account secret, located at `/var/run/secrets/kubernetes.io/serviceaccount/token`
* Do an HTTPS call to `http://kubernetes.default.svc/api/v1/namespaces/{{namespace}}/pods?labelSelector={{selector}}` with the token as an auth header
* Filter returned pods, ignoring: the current pod, pods we are already connected to, pods not running, pods not ready, pods without ip

This process is considered a "tick" and there is one tick every 3 seconds.
