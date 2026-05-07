defmodule Monitorex.Components.Live.InboundRecentPageTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Monitorex.Components.Live.InboundRecentPage

  describe "update/2" do
    test "renders empty state when no events" do
      html = render_component(InboundRecentPage, %{id: "test"})

      assert html =~ "Recent Inbound Requests"
      assert html =~ "Time"
      assert html =~ "Consumer"
      assert html =~ "Method"
      assert html =~ "Route"
      assert html =~ "Status"
      assert html =~ "Duration"
      assert html =~ "No recent inbound requests"
    end

    test "renders filter controls" do
      html = render_component(InboundRecentPage, %{id: "test"})

      assert html =~ "All Consumers"
      assert html =~ "All Routes"
      assert html =~ "Success"
      assert html =~ "Client Error"
    end

    test "renders with filters" do
      html = render_component(InboundRecentPage, %{
        id: "test",
        status_class: "error",
        consumer: "myapp",
        route: "GET:/api/users"
      })

      assert html =~ "Recent Inbound Requests"
    end
  end
end
