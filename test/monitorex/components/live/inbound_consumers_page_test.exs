defmodule Monitorex.Components.Live.InboundConsumersPageTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Monitorex.LiveComponentFixtures

  alias Monitorex.Components.Live.InboundConsumersPage

  setup do
    reset_ets_tables()
    :ok
  end

  describe "update/2" do
    test "renders empty state when no consumers" do
      html = render_component(InboundConsumersPage, %{id: "test"})

      assert html =~ "Inbound Consumers"
      assert html =~ "Total Consumers"
      assert html =~ "Consumer"
      assert html =~ "Requests"
      assert html =~ "Error Rate"
      assert html =~ "Avg Latency"
      assert html =~ "Last Seen"
      assert html =~ "No consumers found"
    end

    test "renders consumers with real data" do
      insert_inbound_event(method: "GET", path: "/api/items", consumer: "svc-a", duration_ms: 15.0)

      insert_inbound_event(
        method: "POST",
        path: "/api/orders",
        consumer: "svc-b",
        status: 500,
        status_class: :server_error,
        duration_ms: 45.0
      )

      html = render_component(InboundConsumersPage, %{id: "test"})

      assert html =~ "svc-a"
      assert html =~ "svc-b"
      assert html =~ "2"
    end
  end

  describe "handle_event/3" do
    test "sort event toggles direction" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          sort_by: "requests",
          sort_dir: "desc"
        }
      }

      assert {:noreply, _socket} =
               InboundConsumersPage.handle_event("sort", %{"key" => "requests"}, socket)

      assert_received {:navigate, url}
      assert url =~ "sort_by=requests"
      assert url =~ "sort_dir=asc"
    end

    test "sort event keeps desc when key changes" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          sort_by: "requests",
          sort_dir: "desc"
        }
      }

      assert {:noreply, _socket} =
               InboundConsumersPage.handle_event("sort", %{"key" => "consumer"}, socket)

      assert_received {:navigate, url}
      assert url =~ "sort_by=consumer"
      assert url =~ "sort_dir=desc"
    end
  end

  describe "sorting branches" do
    test "sorts by consumer, error_rate, avg_latency, last_seen and unknown keys" do
      base_ts = System.system_time(:microsecond)

      # Insert synthetic consumer aggregates directly so every sort key exists.
      :ets.insert(:monitorex_inbound_consumers, {
        "svc-b",
        %{requests: 100, errors: 30, total_duration: 10_000.0, avg_latency: 100.0, last_seen: base_ts}
      })

      :ets.insert(:monitorex_inbound_consumers, {
        "svc-a",
        %{requests: 10, errors: 0, total_duration: 100.0, avg_latency: 10.0, last_seen: base_ts - 1}
      })

      :ets.insert(:monitorex_inbound_consumers, {
        "svc-c",
        %{requests: 1, errors: 0, total_duration: 1.0, avg_latency: 99.0, last_seen: base_ts - 2}
      })

      for sort_by <- ["consumer", "error_rate", "avg_latency", "last_seen", "unknown"] do
        html = render_component(InboundConsumersPage, %{id: "test", sort_by: sort_by, sort_dir: "asc"})
        assert html =~ "svc-a"
        assert html =~ "svc-b"
      end
    end

    test "sorts ascending and descending" do
      insert_inbound_event(method: "GET", path: "/a", consumer: "svc-z")
      insert_inbound_event(method: "GET", path: "/b", consumer: "svc-a")

      asc = render_component(InboundConsumersPage, %{id: "test", sort_by: "consumer", sort_dir: "asc"})
      assert asc =~ "svc-a"

      desc = render_component(InboundConsumersPage, %{id: "test", sort_by: "consumer", sort_dir: "desc"})
      assert desc =~ "svc-z"
    end
  end
end
