defmodule Monitorex.MountOptions do
  @moduledoc """
  Builds the LiveView session and socket assigns for the Monitorex dashboard.

  The dashboard can be mounted under a path prefix (via a router `scope` or by
  mounting the endpoint behind a reverse proxy). The layout must build asset
  and navigation links from that prefix instead of hardcoding root-absolute
  paths. This module captures the request's mount prefix and the dashboard
  options into the LiveView session, and an `on_mount` hook copies them into
  the socket assigns so the root layout can read them.

  `session/2` is invoked by `Monitorex.Router.http_dashboard/1` through the
  `live_session` `:session` option. `on_mount/4` is registered as part of the
  default `:on_mount` hooks.
  """

  import Phoenix.Component

  @doc """
  Returns the LiveView session map for the current request.

  The session is populated with the dashboard mount prefix derived from
  `conn.script_name`, the configured assets path and the LiveSocket path.
  """
  def session(conn, assets_path, socket_path) do
    %{
      "mount_prefix" => mount_prefix_from_conn(conn),
      "assets_path" => assets_path,
      "socket_path" => socket_path
    }
  end

  @doc false
  def on_mount(:default, _params, session, socket) do
    socket =
      socket
      |> assign(:mount_prefix, session["mount_prefix"] || "/")
      |> assign(:assets_path, session["assets_path"] || "/dashboard-assets")
      |> assign(:socket_path, session["socket_path"] || "/live")

    {:cont, socket}
  end

  defp mount_prefix_from_conn(conn) do
    scope_segments =
      conn.script_name ++ Enum.drop(conn.path_info, -map_size(conn.path_params))

    mount_prefix(scope_segments)
  end

  defp mount_prefix([]), do: "/"
  defp mount_prefix(script_name), do: "/" <> Enum.join(script_name, "/")
end
