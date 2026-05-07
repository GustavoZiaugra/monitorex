defmodule Monitorex.Components.Live.OutboundRecentPageTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Monitorex.Components.Live.OutboundRecentPage

  describe "update/2" do
    test "renders empty state when no events" do
      html = render_component(OutboundRecentPage, %{id: "test"})

      assert html =~ "Recent Outbound Requests"
      assert html =~ "Time"
      assert html =~ "Method"
      assert html =~ "URL"
      assert html =~ "Status"
      assert html =~ "Duration"
      assert html =~ "No recent outbound requests"
    end

    test "renders filter controls" do
      html = render_component(OutboundRecentPage, %{id: "test"})

      assert html =~ "2xx"
      assert html =~ "3xx"
      assert html =~ "4xx"
      assert html =~ "5xx"
      assert html =~ "Host"
      assert html =~ "Prev"
      assert html =~ "Next"
    end
  end
end
