defmodule Monitorex.Layouts do
  @moduledoc """
  LiveView layouts for the Monitorex dashboard.

  Provides a root layout with sidebar navigation, flash messages, and
  a main content area.
  """

  use Phoenix.LiveView

  @doc """
  Renders the root layout HTML document.

  Includes:
    * HTML5 doctype and responsive viewport meta
    * Title "Monitorex"
    * CSS and JS asset links
    * Sidebar navigation with "Outbound" and "Inbound" tabs
    * Flash group rendering
    * Main content area yielding `@inner_content`
  """
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Monitorex</title>
        <link rel="stylesheet" href={"/dashboard-assets/app.css"} />
        <script defer src={"/dashboard-assets/app.js"}></script>
      </head>
      <body>
        <nav>
          <h1>Monitorex</h1>
          <button id="nav-toggle" class="nav-toggle" aria-label="Toggle navigation">&#9776;</button>
          <div class="nav-links">
            <a href="/">Outbound</a>
            <a href="/inbound">Inbound</a>
          </div>
        </nav>
        <main>
          <.flash_group flash={@flash} />
          <%= @inner_content %>
        </main>
      </body>
    </html>
    """
  end

  def flash_group(assigns) do
    ~H"""
    <div class="flash-group">
      <%= for {kind, msg} <- Enum.filter(@flash, fn {_k, v} -> v end) do %>
        <div class={"flash flash-#{kind}"} role="alert">
          <%= msg %>
        </div>
      <% end %>
    </div>
    """
  end
end
