defmodule DemoWeb.Router do
  use DemoWeb, :router
  import Monitorex.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # Assets unpiped: protect_from_forgery rejects cross-origin script GETs
  # (403 on app.js), so the asset route must bypass it.
  scope "/" do
    get "/dashboard-assets/*path", Monitorex.Assets, :call
  end

  scope "/" do
    pipe_through :browser
    http_dashboard []
  end
end
