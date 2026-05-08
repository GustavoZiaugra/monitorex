defmodule Monitorex.Layouts do
  @moduledoc """
  LiveView layouts for the Monitorex dashboard.

  Provides a root layout with sidebar navigation, flash messages, and
  a main content area. Fully responsive — sidebar collapses on mobile.
  """

  use Phoenix.LiveView

  @doc """
  Renders the root layout HTML document.

  Includes:
    * HTML5 doctype and responsive viewport meta
    * Title "Monitorex"
    * CSS and JS asset links
    * Sidebar navigation with icons for Outbound, Inbound, and Cluster nodes
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
        <button id="nav-toggle" class="nav-toggle" aria-label="Toggle navigation">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <line x1="3" y1="6" x2="21" y2="6" />
            <line x1="3" y1="12" x2="21" y2="12" />
            <line x1="3" y1="18" x2="21" y2="18" />
          </svg>
        </button>

        <nav>
          <a href="/" class="nav-brand">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M22 12h-4l-3 9L9 3l-3 9H2" />
            </svg>
            Monitorex
          </a>

          <div class="nav-section-label">Dashboard</div>
          <div class="nav-links">
            <a href="/">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M21 16V8a2 2 0 00-1-1.73l-7-4a2 2 0 00-2 0l-7 4A2 2 0 002 8v8a2 2 0 001 1.73l7 4a2 2 0 002 0l7-4A2 2 0 0021 16z" />
                <polyline points="3.27 6.96 12 12.01 20.73 6.96" />
                <line x1="12" y1="22.08" x2="12" y2="12" />
              </svg>
              Outbound
            </a>
            <a href="/outbound_recent">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <polyline points="22 12 18 12 15 21 9 3 6 12 2 12" />
              </svg>
              Outbound Recent
            </a>
            <a href="/timeline">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
                <line x1="9" y1="3" x2="9" y2="21" />
                <line x1="3" y1="9" x2="21" y2="9" />
              </svg>
              Timeline
            </a>
          </div>

          <div class="nav-section-label">Inbound</div>
          <div class="nav-links">
            <a href="/inbound">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z" />
              </svg>
              Overview
            </a>
            <a href="/inbound_consumers">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2" />
                <circle cx="9" cy="7" r="4" />
                <path d="M23 21v-2a4 4 0 00-3-3.87" />
                <path d="M16 3.13a4 4 0 010 7.75" />
              </svg>
              Consumers
            </a>
            <a href="/inbound_recent">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="12" cy="12" r="10" />
                <polyline points="12 6 12 12 16 14" />
              </svg>
              Recent
            </a>
          </div>

          <div class="nav-section-label">Cluster</div>
          <div class="nav-links">
            <a href="/cluster">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <rect x="2" y="2" width="8" height="8" rx="2" />
                <rect x="14" y="2" width="8" height="8" rx="2" />
                <rect x="2" y="14" width="8" height="8" rx="2" />
                <rect x="14" y="14" width="8" height="8" rx="2" />
              </svg>
              Nodes
            </a>
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
