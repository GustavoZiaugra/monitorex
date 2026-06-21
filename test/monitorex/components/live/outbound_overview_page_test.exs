defmodule Monitorex.Components.Live.OutboundOverviewPageTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Monitorex.LiveComponentFixtures

  alias Monitorex.Components.Live.OutboundOverviewPage

  setup do
    reset_ets_tables()
    :ok
  end

  describe "update/2" do
    test "renders summary cards with zero values when no hosts" do
      html = render_component(OutboundOverviewPage, %{id: "test"})

      assert html =~ "Outbound Overview"
      assert html =~ "Total Requests"
      assert html =~ "Error Rate"
      assert html =~ "Avg Latency"
      assert html =~ "0"
      assert html =~ "0%"
      assert html =~ "0ms"
    end

    test "renders host table with columns matching spec" do
      html = render_component(OutboundOverviewPage, %{id: "test"})

      assert html =~ "Host"
      assert html =~ "Client"
      assert html =~ "Requests"
      assert html =~ "Avg"
      assert html =~ "P95"
      assert html =~ "Error Rate"
      assert html =~ "No hosts found"
    end

    test "renders node selector" do
      html = render_component(OutboundOverviewPage, %{id: "test"})

      assert html =~ "All Nodes"
    end

    test "handles sort event" do
      html =
        render_component(OutboundOverviewPage, %{id: "test", sort_by: "host", sort_dir: :asc})

      assert html =~ "Outbound Overview"
      assert html =~ "Host"
    end

    test "renders hosts with real data" do
      insert_outbound_event(method: "GET", path: "/users", duration_ms: 25.0)

      insert_outbound_event(
        method: "POST",
        path: "/orders",
        status: 500,
        status_class: :server_error,
        duration_ms: 120.0
      )

      html = render_component(OutboundOverviewPage, %{id: "test"})

      assert html =~ "api.example.com"
      assert html =~ "2"
      assert html =~ "50.0%"
      assert html =~ "72.5ms"
    end
  end

  describe "handle_event/3" do
    test "navigate event sends navigation message" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          hosts: [],
          sort_by: "requests",
          sort_dir: "desc"
        }
      }

      assert {:noreply, _socket} =
               OutboundOverviewPage.handle_event("navigate", %{"path" => "/host/test"}, socket)

      assert_received {:navigate, "/host/test"}
    end

    test "sort event toggles direction" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          hosts: [],
          sort_by: "requests",
          sort_dir: "desc"
        }
      }

      assert {:noreply, _socket} =
               OutboundOverviewPage.handle_event("sort", %{"key" => "requests"}, socket)

      assert_received {:navigate, url}
      assert url =~ "sort_by=requests"
      assert url =~ "sort_dir=asc"
    end

    test "sort event changes to new key with desc direction" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          hosts: [],
          sort_by: "requests",
          sort_dir: "desc"
        }
      }

      assert {:noreply, _socket} =
               OutboundOverviewPage.handle_event("sort", %{"key" => "host"}, socket)

      assert_received {:navigate, url}
      assert url =~ "sort_by=host"
      assert url =~ "sort_dir=desc"
    end
  end

  describe "sorting branches" do
    test "sorts by client, avg_latency, p95, error_rate and unknown keys" do
      :ets.insert(:monitorex_outbound_hosts, {
        "host-a",
        %{host: "host-a", client: "client-a", requests: 10, errors: 1, total_duration: 100.0, avg_latency: 10.0, p95: 20.0, error_rate: 0.1, last_seen: System.system_time(:microsecond)}
      })

      :ets.insert(:monitorex_outbound_hosts, {
        "host-b",
        %{host: "host-b", client: "client-b", requests: 5, errors: 0, total_duration: 50.0, avg_latency: 10.0, p95: 10.0, error_rate: 0.0, last_seen: System.system_time(:microsecond)}
      })

      for sort_by <- ["client", "avg_latency", "p95", "error_rate", "unknown"] do
        html = render_component(OutboundOverviewPage, %{id: "test", sort_by: sort_by, sort_dir: "asc"})
        assert html =~ "host-a"
        assert html =~ "host-b"
      end
    end
  end
end
