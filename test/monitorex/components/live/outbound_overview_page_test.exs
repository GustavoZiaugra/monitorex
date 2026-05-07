defmodule Monitorex.Components.Live.OutboundOverviewPageTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Monitorex.Components.Live.OutboundOverviewPage

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
      html = render_component(OutboundOverviewPage, %{id: "test", sort_by: "host", sort_dir: :asc})

      assert html =~ "Outbound Overview"
      assert html =~ "Host"
    end
  end
end
