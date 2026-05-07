defmodule Monitorex.Components.Live.HostDetailPageTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Monitorex.Components.Live.HostDetailPage

  describe "update/2" do
    test "renders empty state when host has no data" do
      html = render_component(HostDetailPage, %{id: "test", host: "api.example.com"})

      assert html =~ "Host: api.example.com"
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

      assert {:noreply, _socket} = HostDetailPage.handle_event("sort", %{"key" => "requests"}, socket)
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
  end
end
