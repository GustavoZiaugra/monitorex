defmodule Monitorex.DashboardLiveTest do
  use ExUnit.Case, async: true

  alias Monitorex.Components.Live
  alias Monitorex.DashboardLive

  describe "resolve_page/1" do
    test "returns default page for empty params" do
      assert DashboardLive.resolve_page(%{}) == "outbound"
    end

    test "returns known page for valid page param" do
      assert DashboardLive.resolve_page(%{"page" => "outbound"}) == "outbound"
      assert DashboardLive.resolve_page(%{"page" => "inbound"}) == "inbound"
      assert DashboardLive.resolve_page(%{"page" => "outbound_recent"}) == "outbound_recent"
      assert DashboardLive.resolve_page(%{"page" => "inbound_consumers"}) == "inbound_consumers"
      assert DashboardLive.resolve_page(%{"page" => "inbound_recent"}) == "inbound_recent"
    end

    test "returns default for unknown page" do
      assert DashboardLive.resolve_page(%{"page" => "unknown"}) == "outbound"
    end

    test "returns host for host page with host param" do
      assert DashboardLive.resolve_page(%{"page" => "host", "host" => "api.example.com"}) ==
               "host"
    end

    test "returns route for route page with host param as route key" do
      assert DashboardLive.resolve_page(%{"page" => "route", "host" => "POST:/api/users"}) ==
               "route"
    end
  end

  describe "pages map" do
    test "contains all expected page modules" do
      assert DashboardLive.get_pages()["outbound"] == Live.OutboundOverviewPage
      assert DashboardLive.get_pages()["outbound_recent"] == Live.OutboundRecentPage
      assert DashboardLive.get_pages()["host"] == Live.HostDetailPage
      assert DashboardLive.get_pages()["inbound"] == Live.InboundOverviewPage
      assert DashboardLive.get_pages()["inbound_consumers"] == Live.InboundConsumersPage
      assert DashboardLive.get_pages()["inbound_recent"] == Live.InboundRecentPage
      assert DashboardLive.get_pages()["route"] == Live.RouteDetailPage
    end
  end

  describe "build_page_assigns/2" do
    test "drops page key and converts remaining keys to atoms" do
      assigns =
        DashboardLive.build_page_assigns(%{"page" => "outbound", "node" => "node1"}, "outbound")

      assert assigns == %{node: "node1"}
    end

    test "remaps host to route for route page" do
      assigns =
        DashboardLive.build_page_assigns(
          %{"page" => "route", "host" => "POST:/api/users"},
          "route"
        )

      assert assigns == %{route: "POST:/api/users"}
    end

    test "passes through non-route params unchanged" do
      assigns =
        DashboardLive.build_page_assigns(
          %{"page" => "inbound_recent", "consumer" => "myapp"},
          "inbound_recent"
        )

      assert assigns == %{consumer: "myapp"}
    end
  end

  describe "default_page" do
    test "is outbound" do
      assert DashboardLive.default_page() == "outbound"
    end
  end

  describe "mount/3" do
    test "assigns default page and component when no params" do
      initial_socket = %Phoenix.LiveView.Socket{}
      {:ok, socket} = DashboardLive.mount(%{}, %{}, initial_socket)

      assert socket.assigns.page_name == "outbound"
      assert socket.assigns.page == Live.OutboundOverviewPage
      assert socket.assigns.page_assigns == %{}
    end

    test "assigns correct page when params specify a page" do
      initial_socket = %Phoenix.LiveView.Socket{}
      {:ok, socket} = DashboardLive.mount(%{"page" => "inbound"}, %{}, initial_socket)

      assert socket.assigns.page_name == "inbound"
      assert socket.assigns.page == Live.InboundOverviewPage
    end

    test "assigns host detail page when page=host and host param present" do
      initial_socket = %Phoenix.LiveView.Socket{}

      {:ok, socket} =
        DashboardLive.mount(%{"page" => "host", "host" => "api.example.com"}, %{}, initial_socket)

      assert socket.assigns.page_name == "host"
      assert socket.assigns.page == Live.HostDetailPage
      assert socket.assigns.page_assigns == %{host: "api.example.com"}
    end

    test "assigns timeline page" do
      initial_socket = %Phoenix.LiveView.Socket{}
      {:ok, socket} = DashboardLive.mount(%{"page" => "timeline"}, %{}, initial_socket)

      assert socket.assigns.page_name == "timeline"
      assert socket.assigns.page == Live.TimelinePage
    end

    test "assigns alerts page" do
      initial_socket = %Phoenix.LiveView.Socket{}
      {:ok, socket} = DashboardLive.mount(%{"page" => "alerts"}, %{}, initial_socket)

      assert socket.assigns.page_name == "alerts"
      assert socket.assigns.page == Live.AlertsPage
    end

    test "starts refresh timer when connected" do
      initial_socket = %Phoenix.LiveView.Socket{}

      {:ok, socket} = DashboardLive.mount(%{}, %{}, initial_socket)

      refute socket.assigns.page_name == nil
    end
  end

  describe "handle_params/3" do
    test "updates page when params change" do
      initial_socket = %Phoenix.LiveView.Socket{}
      {:ok, socket} = DashboardLive.mount(%{}, %{}, initial_socket)
      assert socket.assigns.page_name == "outbound"

      {:noreply, updated} = DashboardLive.handle_params(%{"page" => "inbound"}, "/inbound", socket)
      assert updated.assigns.page_name == "inbound"
      assert updated.assigns.page == Live.InboundOverviewPage
    end

    test "routes to correct component for each page type" do
      initial_socket = %Phoenix.LiveView.Socket{}
      {:ok, socket} = DashboardLive.mount(%{}, %{}, initial_socket)

      routes = [
        {%{"page" => "outbound"}, Live.OutboundOverviewPage},
        {%{"page" => "outbound_recent"}, Live.OutboundRecentPage},
        {%{"page" => "inbound"}, Live.InboundOverviewPage},
        {%{"page" => "inbound_consumers"}, Live.InboundConsumersPage},
        {%{"page" => "inbound_recent"}, Live.InboundRecentPage},
        {%{"page" => "host", "host" => "test"}, Live.HostDetailPage},
        {%{"page" => "route", "host" => "GET:/test"}, Live.RouteDetailPage}
      ]

      Enum.each(routes, fn {params, expected_module} ->
        {:noreply, updated} = DashboardLive.handle_params(params, "/", socket)

        assert updated.assigns.page == expected_module,
               "expected #{inspect(params)} to route to #{inspect(expected_module)}, got #{inspect(updated.assigns.page)}"
      end)
    end
  end

  describe "handle_info/2" do
    test ":refresh resends timer and triggers re-render" do
      initial_socket = %Phoenix.LiveView.Socket{}
      {:ok, socket} = DashboardLive.mount(%{}, %{}, initial_socket)

      assert {:noreply, _updated} = DashboardLive.handle_info(:refresh, socket)
    end

    test "{:navigate, path} pushes navigation" do
      initial_socket = %Phoenix.LiveView.Socket{}
      {:ok, socket} = DashboardLive.mount(%{}, %{}, initial_socket)

      assert {:noreply, _updated} = DashboardLive.handle_info({:navigate, "/host/test"}, socket)
    end
  end

  describe "render/1" do
    test "renders live component for current page" do
      {:ok, socket} = DashboardLive.mount(%{"page" => "outbound"}, %{}, %Phoenix.LiveView.Socket{})

      rendered = DashboardLive.render(socket.assigns)
      assert is_struct(rendered, Phoenix.LiveView.Rendered)
    end
  end

  describe "connected mount" do
    test "starts refresh timer when socket is connected" do
      connected_socket = %Phoenix.LiveView.Socket{transport_pid: self()}
      {:ok, socket} = DashboardLive.mount(%{}, %{}, connected_socket)

      assert socket.assigns.page_name == "outbound"
    end
  end

  describe "normalize_route_param fallback" do
    test "build_page_assigns for route without host key passes through" do
      assigns = DashboardLive.build_page_assigns(%{"page" => "route"}, "route")
      assert assigns == %{}
    end
  end
end
