defmodule Monitorex.Components.Live.HostDetailPageTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Monitorex.LiveComponentFixtures

  alias Monitorex.Components.Live.HostDetailPage

  setup do
    reset_ets_tables()
    :ok
  end

  describe "update/2" do
    test "renders empty state when host has no data" do
      html = render_component(HostDetailPage, %{id: "test", host: "api.example.com"})

      assert html =~ "api.example.com"
      assert html =~ "Total Requests"
      assert html =~ "Endpoints"
      assert html =~ "Avg Latency"
      assert html =~ "Error Rate"
    end

    test "renders endpoints table with empty state" do
      html = render_component(HostDetailPage, %{id: "test", host: "api.example.com"})

      assert html =~ "Endpoints"
      assert html =~ "Path"
      assert html =~ "Requests"
      assert html =~ "Avg"
      assert html =~ "Error Rate"
    end

    test "renders recent requests table with empty state" do
      html = render_component(HostDetailPage, %{id: "test", host: "api.example.com"})

      assert html =~ "Recent Requests"
      assert html =~ "No endpoints found"
      assert html =~ "No recent requests for this host"
    end

    test "renders host metrics and endpoints when data exists" do
      insert_outbound_event(method: "GET", path: "/users", duration_ms: 25.0)

      insert_outbound_event(
        method: "POST",
        path: "/orders",
        status: 500,
        status_class: :server_error,
        duration_ms: 120.0
      )

      html = render_component(HostDetailPage, %{id: "test", host: "api.example.com"})

      assert html =~ "api.example.com"
      assert html =~ "2"
      assert html =~ "/users"
      assert html =~ "/orders"
      assert html =~ "25"
      assert html =~ "120"
    end
  end

  describe "handle_event/3" do
    test "sort event toggles direction for same key" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          host: "example.com",
          sort_by: "requests",
          sort_dir: "asc"
        }
      }

      assert {:noreply, _socket} =
               HostDetailPage.handle_event("sort", %{"key" => "requests"}, socket)

      assert_received {:navigate, url}
      assert url =~ "sort_by=requests"
      assert url =~ "sort_dir=desc"
    end

    test "sort event changes to new key with ascending direction" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          host: "example.com",
          sort_by: "requests",
          sort_dir: "desc"
        }
      }

      assert {:noreply, _socket} = HostDetailPage.handle_event("sort", %{"key" => "path"}, socket)
      assert_received {:navigate, url}
      assert url =~ "sort_by=path"
      assert url =~ "sort_dir=asc"
    end

    test "sort event ignores invalid keys" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          host: "example.com",
          sort_by: "requests",
          sort_dir: "desc"
        }
      }

      assert_raise FunctionClauseError, fn ->
        HostDetailPage.handle_event("sort", %{"key" => "invalid"}, socket)
      end
    end

    test "go_recent_page event navigates with page" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          host: "example.com",
          sort_by: "requests",
          sort_dir: "desc"
        }
      }

      assert {:noreply, _socket} =
               HostDetailPage.handle_event("go_recent_page", %{"page" => "2"}, socket)

      assert_received {:navigate, url}
      assert url =~ "recent_page=2"
      assert url =~ "host=example.com"
    end
  end
end
