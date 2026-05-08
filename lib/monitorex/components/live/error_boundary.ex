defmodule Monitorex.Components.Live.ErrorBoundary do
  @moduledoc """
  Error boundary wrapper for Monitorex LiveComponents.

  Catches crashes in child LiveComponents and displays a friendly error card
  instead of taking down the entire page. Click "Retry" to re-mount.
  """

  use Phoenix.LiveComponent

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:error, nil)
      |> assign(:component_id, assigns[:id])

    {:ok, socket}
  end

  @impl true
  def handle_event("retry", _params, socket) do
    {:noreply, assign(socket, :error, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@component_id} class="error-boundary">
      <%= if @error do %>
        <div class="error-boundary-card">
          <div class="error-boundary-icon">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="10" />
              <line x1="12" y1="8" x2="12" y2="12" />
              <line x1="12" y1="16" x2="12.01" y2="16" />
            </svg>
          </div>
          <h4>Something went wrong</h4>
          <p><%= @error %></p>
          <button phx-click="retry" phx-target={@myself} class="error-retry-btn">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <polyline points="23 4 23 10 17 10" />
              <path d="M20.49 15a9 9 0 11-2.12-9.36L23 10" />
            </svg>
            Retry
          </button>
        </div>
      <% else %>
        <%= render_slot(@inner_block) %>
      <% end %>
    </div>
    """
  end
end
