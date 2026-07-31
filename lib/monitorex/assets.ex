defmodule Monitorex.Assets do
  @moduledoc """
  Plug for serving Monitorex dashboard static assets (CSS and JS).

  Reads the asset files at **compile time** and serves them with
  far-future cache headers.

  ## Usage

  In your router:

      get "/dashboard-assets/*path", Monitorex.Assets, :call

  Or in a plug pipeline:

      plug Monitorex.Assets, at: "/dashboard-assets"
  """

  use Plug.Builder

  alias Plug.Conn

  @external_resource Path.join(__DIR__, "../../priv/static/app.css")
  @external_resource Path.join(__DIR__, "../../priv/static/app.js")

  @css_path Path.join(__DIR__, "../../priv/static/app.css")
  @js_path Path.join(__DIR__, "../../priv/static/app.js")

  @css_content File.read!(@css_path)
  @js_content File.read!(@js_path)

  @css_hash Base.encode16(:crypto.hash(:md5, @css_content), case: :lower)
  @js_hash Base.encode16(:crypto.hash(:md5, @js_content), case: :lower)

  @doc """
  Returns the MD5 hex digest of the CSS file contents.
  """
  def css_hash, do: @css_hash

  @doc """
  Returns the MD5 hex digest of the JS file contents.
  """
  def js_hash, do: @js_hash

  @doc """
  Plug init callback.

  ## Options

    * `:at` — accepted for backwards compatibility (default: `"/dashboard-assets"`).
      The request path is matched by its trailing filename segment, so the
      option no longer affects serving.
  """
  def init(_opts) do
    %{at: "/dashboard-assets"}
  end

  @doc """
  Plug call callback. Serves the requested asset file or returns 404.

  The filename is matched by the trailing path segment, so assets are served
  correctly when the dashboard is mounted under any path prefix — whether the
  prefix comes from the endpoint mount (`conn.script_name`), a router `scope`,
  a reverse proxy, or a custom `assets_path`. The router route pattern (e.g.
  `get "/dashboard-assets/*path"`) guarantees the request reached this plug
  only under the configured asset mount path.
  """
  def call(conn, _opts) do
    cond do
      List.ends_with?(conn.path_info, ["app.css"]) -> serve_css(conn)
      List.ends_with?(conn.path_info, ["app.js"]) -> serve_js(conn)
      true -> serve_not_found(conn)
    end
  end

  defp serve_css(conn) do
    conn
    |> put_resp_content_type("text/css")
    |> put_cache_headers()
    |> send_resp(200, @css_content)
  end

  defp serve_js(conn) do
    conn
    |> put_resp_content_type("application/javascript")
    |> put_cache_headers()
    |> send_resp(200, @js_content)
  end

  defp serve_not_found(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Not Found")
  end

  defp put_cache_headers(conn) do
    Conn.put_resp_header(conn, "cache-control", "public, max-age=31536000, immutable")
  end
end
