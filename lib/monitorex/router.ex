defmodule Monitorex.Router do
  @moduledoc """
  Router macros for embedding the Monitorex dashboard in your Phoenix application.

  ## Usage

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        import Monitorex.Router

        scope "/monitorex" do
          http_dashboard []
        end
      end

  The pipeline that runs the dashboard routes must include
  `:protect_from_forgery` (or `Plug.CSRFProtection`). The dashboard layout
  reads the CSRF token to authenticate the LiveView socket connection, and the
  LiveView client sends it back as `_csrf_token`.
  """

  @doc """
  Defines the Monitorex HTTP dashboard routes.

  ## Options

    * `:live_view` — module to use as the dashboard LiveView (default: `Monitorex.DashboardLive`)
    * `:layout` — root layout module (default: `{Monitorex.Layouts, :root}`)
    * `:assets_path` — asset mount path (default: `"/dashboard-assets"`)
    * `:socket_path` — LiveSocket path of the host application's
      `Phoenix.LiveView.Socket` endpoint (default: `"/live"`)
    * `:on_mount` — additional on_mount hooks. The default is
      `[Monitorex.Authentication, Monitorex.MountOptions]`. If you override
      this option you **must include both** `Monitorex.Authentication` (auth)
      and `Monitorex.MountOptions` (which assigns the mount prefix, assets path
      and socket path to the socket for the root layout); omitting
      `Monitorex.MountOptions` leaves the layout with its default unprefixed
      hrefs and `/live` socket path.
    * `:api_path` — API mount path (default: `"/api"`). Set to `nil` or `false` to disable the REST API entirely.

  ## Example

      http_dashboard live_view: MyApp.CustomLive

  This generates:

      live_session :monitorex_dashboard,
        root_layout: {Monitorex.Layouts, :root},
        on_mount: [Monitorex.Authentication, Monitorex.MountOptions],
        session: {Monitorex.MountOptions, :session, ["/dashboard-assets", "/live"]} do
        get "/dashboard-assets/*path", Monitorex.Assets, :call
        live "/", Monitorex.DashboardLive, :index
        live "/:page", Monitorex.DashboardLive, :index
        live "/:page/:host", Monitorex.DashboardLive, :index
      end

      # API routes (outside live_session, no auth)
      forward "/api", Monitorex.ApiPlug
  """
  defmacro http_dashboard(opts \\ []) do
    live_view = Keyword.get(opts, :live_view, Monitorex.DashboardLive)
    layout = Keyword.get(opts, :layout, {Monitorex.Layouts, :root})
    assets_path = Keyword.get(opts, :assets_path, "/dashboard-assets")
    socket_path = Keyword.get(opts, :socket_path, "/live")
    health_path = Keyword.get(opts, :health_path, "/monitorex/health")
    on_mount = Keyword.get(opts, :on_mount, [Monitorex.Authentication, Monitorex.MountOptions])
    api_path = Keyword.get(opts, :api_path, "/api")

    api_forward =
      if api_path not in [nil, false] do
        quote do
          # REST API (separate pipeline, no auth)
          forward(unquote(api_path), Monitorex.ApiPlug)
        end
      end

    quote do
      import Phoenix.LiveView.Router

      # Health check endpoint (no auth)
      get(unquote(health_path), Monitorex.HealthPlug, :call)

      # Export endpoint (no auth — generates downloadable CSV/JSON)
      get("/export/:page/:format", Monitorex.ExportPlug, :call)

      # Register asset routes
      get(unquote(assets_path <> "/*path"), Monitorex.Assets, :call)

      unquote(api_forward)

      # Define the live session with root layout and authentication
      live_session :monitorex_dashboard,
        root_layout: unquote(layout),
        on_mount: unquote(on_mount),
        session: {Monitorex.MountOptions, :session, [unquote(assets_path), unquote(socket_path)]} do
        live("/", unquote(live_view), :index)
        live("/:page", unquote(live_view), :index)
        live("/:page/:host", unquote(live_view), :index)
      end
    end
  end
end
