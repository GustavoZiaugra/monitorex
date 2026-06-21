defmodule Monitorex.Components.Live.TimelinePageTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Monitorex.LiveComponentFixtures

  alias Monitorex.Components.Live.TimelinePage
  alias Monitorex.HeaderRedactor

  describe "update/2" do
    setup do
      reset_ets_tables()
      :ok
    end

    test "renders page header and empty state when no events" do
      html =
        render_component(TimelinePage, %{
          id: "timeline-test",
          direction: "outbound"
        })

      assert html =~ "Request Timeline"
      assert html =~ "Real-time request/response inspector"
      assert html =~ "No matching outbound events"
      assert html =~ "Outbound"
      assert html =~ "Inbound"
    end

    test "renders inbound tab selected when direction=inbound" do
      html =
        render_component(TimelinePage, %{
          id: "timeline-test",
          direction: "inbound"
        })

      assert html =~ "No matching inbound events"
    end

    test "renders grouped outbound events" do
      insert_outbound_event(
        method: "GET",
        path: "/users",
        request_headers: [{"authorization", "secret"}],
        response_headers: [{"content-type", "application/json"}]
      )

      html =
        render_component(TimelinePage, %{
          id: "timeline-test",
          direction: "outbound"
        })

      assert html =~ "api.example.com"
      assert html =~ "/users"
      assert html =~ "GET"
      assert html =~ "200"
    end

    test "renders selected event details" do
      ts = System.system_time(:microsecond)

      insert_inbound_event(
        method: "POST",
        status: 201,
        timestamp: ts,
        request_body: "{}",
        response_body: "{\"ok\":true}"
      )

      html =
        render_component(TimelinePage, %{
          id: "timeline-test",
          direction: "inbound",
          selected: to_string(ts)
        })

      assert html =~ "Request Details"
      assert html =~ "app.local"
      assert html =~ "/api/items"
      assert html =~ "POST"
      assert html =~ "201"
      assert html =~ "Request Body"
      assert html =~ "Response Body"
    end

    test "filters events by search query" do
      insert_outbound_event(method: "GET", path: "/users", full_url: "https://api.example.com/users")

      insert_outbound_event(
        method: "POST",
        path: "/orders",
        full_url: "https://api.example.com/orders"
      )

      html =
        render_component(TimelinePage, %{
          id: "timeline-test",
          direction: "outbound",
          search: "orders"
        })

      assert html =~ "/orders"
      refute html =~ "/users"
    end

    test "filters events by status" do
      insert_outbound_event(method: "GET", path: "/users", status: 200, status_class: :success)

      insert_outbound_event(
        method: "POST",
        path: "/orders",
        status: 500,
        status_class: :server_error
      )

      html =
        render_component(TimelinePage, %{
          id: "timeline-test",
          direction: "outbound",
          status: "server_error"
        })

      assert html =~ "500"
      refute html =~ "200"
    end

    test "filters events by method" do
      insert_outbound_event(method: "GET", path: "/users", full_url: "https://api.example.com/users")

      insert_outbound_event(
        method: "POST",
        path: "/orders",
        full_url: "https://api.example.com/orders"
      )

      html =
        render_component(TimelinePage, %{
          id: "timeline-test",
          direction: "outbound",
          method: "POST"
        })

      assert html =~ "/orders"
      refute html =~ "/users"
    end

    test "shows load more button when events exceed initial load" do
      for i <- 1..60 do
        insert_outbound_event(path: "/req#{i}")
      end

      html =
        render_component(TimelinePage, %{
          id: "timeline-test",
          direction: "outbound"
        })

      assert html =~ "Load"
      assert html =~ "more events"

      html =
        render_component(TimelinePage, %{
          id: "timeline-test",
          direction: "outbound",
          show_all: "true"
        })

      refute html =~ "Load"
    end

    test "renders selected event with headers, error and body truncation" do
      ts = System.system_time(:microsecond)

      insert_outbound_event(
        method: "PUT",
        path: "/users",
        status: 301,
        status_class: :redirect,
        timestamp: ts,
        error: "connection refused",
        request_headers: [{"authorization", "secret"}],
        response_headers: [{"content-type", "application/json"}],
        request_body: String.duplicate("x", 2500),
        response_body: "ok"
      )

      html =
        render_component(TimelinePage, %{
          id: "timeline-test",
          direction: "outbound",
          selected: to_string(ts)
        })

      assert html =~ "connection refused"
      assert html =~ "••••redacted••••"
      assert html =~ "content-type"
      assert html =~ "application/json"
      assert html =~ "PUT"
      assert html =~ "301"
    end

    test "renders older time buckets" do
      now_us = System.system_time(:microsecond)

      insert_outbound_event(
        path: "/old",
        timestamp: now_us - 2 * 60 * 1_000_000
      )

      html =
        render_component(TimelinePage, %{
          id: "timeline-test",
          direction: "outbound"
        })

      assert html =~ "old" or html =~ "Older" or html =~ "min ago"
    end

    test "direction fallback returns empty events" do
      html =
        render_component(TimelinePage, %{
          id: "timeline-test",
          direction: "unknown"
        })

      assert html =~ "No matching"
    end
  end

  describe "handle_event/3" do
    test "select_direction sends navigation with direction param" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          direction: "outbound",
          selected_event: nil
        }
      }

      assert {:noreply, _socket} =
               TimelinePage.handle_event("select_direction", %{"direction" => "inbound"}, socket)

      assert_received {:navigate, url}
      assert url =~ "direction=inbound"
    end

    test "select_event sends navigation with selected param" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          direction: "outbound",
          selected_event: nil
        }
      }

      assert {:noreply, _socket} =
               TimelinePage.handle_event("select_event", %{"id" => "12345"}, socket)

      assert_received {:navigate, url}
      assert url =~ "selected=12345"
    end

    test "search sends navigation with search param" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          direction: "outbound",
          search_query: "",
          filter_status: "",
          filter_method: ""
        }
      }

      assert {:noreply, _socket} =
               TimelinePage.handle_event("search", %{"search" => "users"}, socket)

      assert_received {:navigate, url}
      assert url =~ "search=users"
    end

    test "filter_status sends navigation with status param" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          direction: "outbound",
          search_query: "",
          filter_status: "",
          filter_method: ""
        }
      }

      assert {:noreply, _socket} =
               TimelinePage.handle_event("filter_status", %{"status" => "500"}, socket)

      assert_received {:navigate, url}
      assert url =~ "status=500"
    end

    test "filter_method sends navigation with method param" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          direction: "outbound",
          search_query: "",
          filter_status: "",
          filter_method: ""
        }
      }

      assert {:noreply, _socket} =
               TimelinePage.handle_event("filter_method", %{"method" => "POST"}, socket)

      assert_received {:navigate, url}
      assert url =~ "method=POST"
    end

    test "load_more sends navigation with show_all param" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          direction: "outbound",
          search_query: "",
          filter_status: "",
          filter_method: ""
        }
      }

      assert {:noreply, _socket} = TimelinePage.handle_event("load_more", %{}, socket)
      assert_received {:navigate, url}
      assert url =~ "show_all=true"
    end

    test "clear_filters resets to base url" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          direction: "inbound"
        }
      }

      assert {:noreply, _socket} = TimelinePage.handle_event("clear_filters", %{}, socket)
      assert_received {:navigate, url}
      assert url =~ "page=timeline"
      assert url =~ "direction=inbound"
    end

    test "filter_status ignores invalid status atom" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          direction: "outbound",
          search_query: "",
          filter_status: "",
          filter_method: ""
        }
      }

      assert {:noreply, _socket} =
               TimelinePage.handle_event("filter_status", %{"status" => "not_an_atom"}, socket)

      assert_received {:navigate, url}
      assert url =~ "status=not_an_atom"
    end

    test "build_filter_url includes all active filters" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          direction: "inbound",
          search_query: "users",
          filter_status: "server_error",
          filter_method: "POST",
          show_all: true,
          selected: "123"
        }
      }

      assert {:noreply, _socket} =
               TimelinePage.handle_event("select_event", %{"id" => "456"}, socket)

      assert_received {:navigate, url}
      assert url =~ "direction=inbound"
      assert url =~ "search=users"
      assert url =~ "status=server_error"
      assert url =~ "method=POST"
      assert url =~ "show_all=true"
      assert url =~ "selected=456"
    end
  end

  describe "header redaction formatting" do
    test "redact_headers marks authorization as redacted" do
      headers = [{"authorization", "Bearer secret123"}, {"content-type", "application/json"}]
      redacted = HeaderRedactor.default_redacted_headers()

      result = HeaderRedactor.redact_headers(headers, redacted)
      assert {"authorization", "••••redacted••••"} in result
      assert {"content-type", "application/json"} in result
    end

    test "redact_headers handles case-insensitive matching" do
      headers = [{"Authorization", "Bearer token"}, {"X-Api-Key", "abc123"}]
      redacted = HeaderRedactor.default_redacted_headers()

      result = HeaderRedactor.redact_headers(headers, redacted)
      assert {"Authorization", "••••redacted••••"} in result
      assert {"X-Api-Key", "••••redacted••••"} in result
    end
  end
end
