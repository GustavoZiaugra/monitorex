defmodule Monitorex.Components.Live.LiveViewIntegrationTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Monitorex.LiveComponentFixtures

  @endpoint Monitorex.TestEndpoint

  alias Monitorex.Components.Live.HostDetailPage
  alias Monitorex.Components.Live.InboundConsumersPage
  alias Monitorex.Components.Live.InboundOverviewPage
  alias Monitorex.Components.Live.InboundRecentPage
  alias Monitorex.Components.Live.OutboundOverviewPage
  alias Monitorex.Components.Live.OutboundRecentPage
  alias Monitorex.Components.Live.RouteDetailPage
  alias Monitorex.Components.Live.TimelinePage

  @navigate_table :monitorex_test_navigations
  @event_attrs ["phx-click", "phx-change", "phx-keyup", "phx-blur", "phx-submit"]

  setup do
    reset_ets_tables()
    :ets.new(@navigate_table, [:named_table, :public, :set])
    :ok
  end

  describe "every event binding carries phx-target" do
    test "TimelinePage" do
      html = render_component(TimelinePage, %{id: "timeline"})
      assert all_bindings_targeted?(html)
    end

    test "OutboundRecentPage" do
      html = render_component(OutboundRecentPage, %{id: "outbound_recent"})
      assert all_bindings_targeted?(html)
    end

    test "InboundRecentPage" do
      html = render_component(InboundRecentPage, %{id: "inbound_recent"})
      assert all_bindings_targeted?(html)
    end
  end

  defp all_bindings_targeted?(html) do
    selector = Enum.map_join(@event_attrs, ", ", &"[#{&1}]")

    html
    |> Floki.parse_fragment!()
    |> Floki.find(selector)
    |> Enum.all?(fn {_tag, attrs, _children} -> List.keyfind(attrs, "phx-target", 0) != nil end)
  end

  defp mount_page(component, assigns \\ %{}) do
    session = %{"component" => component, "assigns" => Map.new(assigns)}
    {:ok, view, _html} = live_isolated(build_conn(), Monitorex.TestPageHost, session: session)
    view
  end

  defp last_navigate do
    wait_for(fn ->
      case :ets.tab2list(@navigate_table) do
        [{_pid, url}] -> {:ok, url}
        _ -> :retry
      end
    end)
  end

  defp wait_for(fun, attempts \\ 50)

  defp wait_for(fun, attempts) when attempts > 0 do
    case fun.() do
      {:ok, result} ->
        result

      :retry ->
        Process.sleep(10)
        wait_for(fun, attempts - 1)
    end
  end

  defp wait_for(_fun, _attempts), do: flunk("timed out waiting for navigate message")

  describe "TimelinePage events route to the component" do
    test "select_direction" do
      view = mount_page(TimelinePage, direction: "outbound")

      view |> element("button[phx-value-direction=\"inbound\"]") |> render_click()

      assert last_navigate() =~ "direction=inbound"
    end

    test "select_event" do
      insert_outbound_event()
      view = mount_page(TimelinePage, direction: "outbound")

      view |> element(".timeline-item") |> render_click()

      assert last_navigate() =~ "selected="
    end

    test "search (phx-keyup)" do
      view = mount_page(TimelinePage, direction: "outbound")

      view
      |> element(".tl-search-input")
      |> render_keyup(%{"search" => "users"})

      assert last_navigate() =~ "search=users"
    end

    test "filter_status" do
      view = mount_page(TimelinePage, direction: "outbound")

      view |> element("button[phx-value-status=\"success\"]") |> render_click()

      assert last_navigate() =~ "status=success"
    end

    test "filter_method" do
      view = mount_page(TimelinePage, direction: "outbound")

      view |> element("button[phx-value-method=\"POST\"]") |> render_click()

      assert last_navigate() =~ "method=POST"
    end

    test "load_more" do
      for i <- 1..60 do
        insert_outbound_event(path: "/req#{i}")
      end

      view = mount_page(TimelinePage, direction: "outbound")

      view |> element(".tl-load-more") |> render_click()

      assert last_navigate() =~ "show_all=true"
    end

    test "clear_filters" do
      view = mount_page(TimelinePage, direction: "outbound", status: "success")

      view |> element(".tl-clear-btn") |> render_click()

      assert last_navigate() =~ "page=timeline"
      assert last_navigate() =~ "direction=outbound"
    end
  end

  describe "OutboundRecentPage events route to the component" do
    test "filter_status_class" do
      view = mount_page(OutboundRecentPage)

      view |> element("span[phx-value-status_class=\"5xx\"]") |> render_click()

      assert last_navigate() =~ "status_class=5xx"
    end

    test "filter_host" do
      view = mount_page(OutboundRecentPage)

      view
      |> element(".filter-input")
      |> render_change(%{"host" => "api.example.com"})

      assert last_navigate() =~ "host=api.example.com"
    end

    test "go_page via pagination" do
      for i <- 1..60 do
        insert_outbound_event(path: "/req#{i}")
      end

      view = mount_page(OutboundRecentPage)

      view |> element("button.page-btn", "2") |> render_click()

      assert last_navigate() =~ "page=2"
    end
  end

  describe "InboundRecentPage events route to the component" do
    test "filter_status_class" do
      view = mount_page(InboundRecentPage)

      view |> element("span[phx-value-status_class=\"4xx\"]") |> render_click()

      assert last_navigate() =~ "status_class=4xx"
    end

    test "filter_consumer" do
      view = mount_page(InboundRecentPage)

      view
      |> element("select[phx-change=filter_consumer]")
      |> render_change(%{"consumer" => "svc-a"})

      assert last_navigate() =~ "consumer=svc-a"
    end

    test "filter_route" do
      view = mount_page(InboundRecentPage)

      view
      |> element("select[phx-change=filter_route]")
      |> render_change(%{"route" => "GET:/api/items"})

      assert last_navigate() =~ "route=GET:/api/items"
    end

    test "go_page via pagination" do
      for i <- 1..60 do
        insert_inbound_event(path: "/req#{i}")
      end

      view = mount_page(InboundRecentPage)

      view |> element("button.page-btn", "2") |> render_click()

      assert last_navigate() =~ "page=2"
    end
  end

  describe "OutboundOverviewPage events route to the component" do
    test "sort via data_table" do
      view = mount_page(OutboundOverviewPage)

      view |> element("th[phx-value-key=\"requests\"]") |> render_click()

      assert last_navigate() =~ "sort_by=requests"
    end
  end

  describe "InboundOverviewPage events route to the component" do
    test "sort via data_table" do
      view = mount_page(InboundOverviewPage)

      view |> element("th[phx-value-key=\"requests\"]") |> render_click()

      assert last_navigate() =~ "sort_by=requests"
    end
  end

  describe "InboundConsumersPage events route to the component" do
    test "sort via data_table" do
      view = mount_page(InboundConsumersPage)

      view |> element("th[phx-value-key=\"consumer\"]") |> render_click()

      assert last_navigate() =~ "sort_by=consumer"
    end
  end

  describe "HostDetailPage events route to the component" do
    test "sort via data_table" do
      view = mount_page(HostDetailPage, host: "api.example.com")

      view |> element("th[phx-value-key=\"path\"]") |> render_click()

      assert last_navigate() =~ "sort_by=path"
    end

    test "go_recent_page via pagination" do
      for i <- 1..25 do
        insert_outbound_event(path: "/req#{i}", host: "api.example.com")
      end

      view = mount_page(HostDetailPage, host: "api.example.com")

      view |> element("button.page-btn", "2") |> render_click()

      assert last_navigate() =~ "page=2"
    end
  end

  describe "RouteDetailPage events route to the component" do
    test "sort via data_table" do
      view = mount_page(RouteDetailPage, route: "GET:/api")

      view |> element("th[phx-value-key=\"consumer\"]") |> render_click()

      assert last_navigate() =~ "sort_by=consumer"
    end

    test "go_recent_page via pagination" do
      for i <- 1..25 do
        insert_inbound_event(path: "/api/items")
      end

      view = mount_page(RouteDetailPage, route: "GET:/api/items")

      view |> element("button.page-btn", "2") |> render_click()

      assert last_navigate() =~ "page=2"
    end
  end
end
