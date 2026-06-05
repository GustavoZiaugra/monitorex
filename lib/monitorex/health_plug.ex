defmodule Monitorex.HealthPlug do
  @moduledoc """
  Plug that serves a JSON health check endpoint for Monitorex.

  Used by load balancers, Kubernetes liveness probes, and external
  monitoring systems.  No authentication required.

  ## Usage

  In your router:

      scope "/" do
        forward "/monitorex/health", Monitorex.HealthPlug
      end
  """

  import Plug.Conn

  alias Monitorex.Health

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    health = Health.check()
    status_code = health_status_to_http(health.status)

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("access-control-allow-origin", "*")
    |> send_resp(status_code, Jason.encode!(health))
  end

  defp health_status_to_http(:healthy), do: 200
  defp health_status_to_http(:degraded), do: 200
  defp health_status_to_http(:unhealthy), do: 503
end
