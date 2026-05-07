defmodule Monitorex.Components.Live.InboundOverviewPageTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Monitorex.Components.Live.InboundOverviewPage

  describe "update/2" do
    test "renders summary cards with zero values when no routes" do
      html = render_component(InboundOverviewPage, %{id: "test"})

      assert html =~ "Inbound Overview"
      assert html =~ "Total Requests"
      assert html =~ "Routes"
      assert html =~ "Error Rate"
      assert html =~ "0%"
    end

    test "renders routes table with empty state" do
      html = render_component(InboundOverviewPage, %{id: "test"})

      assert html =~ "Method"
      assert html =~ "Route"
      assert html =~ "Requests"
      assert html =~ "P95"
      assert html =~ "No routes found"
    end
  end
end
