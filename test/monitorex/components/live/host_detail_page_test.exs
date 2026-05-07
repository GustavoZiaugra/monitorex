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
      assert html =~ "No endpoints found for this host"
      assert html =~ "No recent requests for this host"
    end
  end
end
