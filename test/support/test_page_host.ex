defmodule Monitorex.TestPageHost do
  @moduledoc """
  Minimal test-only LiveView that mounts a single Monitorex page component.

  Deliberately defines NO `handle_event/3`, mirroring `Monitorex.DashboardLive`
  (which also has none). This makes the LiveViewTest integration tests fail
  loudly if a page component's `phx-*` bindings lack `phx-target={@myself}`:
  the event leaks to this host and raises `UndefinedFunctionError`.

  Captures `{:navigate, path}` messages (sent by page components) into the
  `:monitorex_test_navigations` ETS table so tests can assert the exact URL
  the component requested. The table is created by the test setup.
  """
  use Phoenix.LiveView

  @impl true
  def mount(params, session, socket) do
    _params = normalize_params(params)
    page = Map.get(session, "component") || Monitorex.Components.Live.OutboundOverviewPage
    page_assigns = Map.get(session, "assigns") || %{}
    {:ok, assign(socket, page: page, page_assigns: page_assigns)}
  end

  @impl true
  def handle_info({:navigate, path}, socket) do
    if :ets.info(:monitorex_test_navigations) != :undefined do
      :ets.insert(:monitorex_test_navigations, {self(), path})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component id="page" module={@page} {@page_assigns} />
    """
  end

  defp normalize_params(:not_mounted_at_router), do: %{}
  defp normalize_params(params) when is_map(params), do: params
end
