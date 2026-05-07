defmodule Monitorex.Components.Live.InboundConsumersPageTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Monitorex.Components.Live.InboundConsumersPage

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
  end
end
