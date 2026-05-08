defmodule Monitorex.Components.Live.TimelinePageTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Monitorex.Components.Live.TimelinePage
  alias Monitorex.HeaderRedactor

  describe "update/2" do
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
