defmodule Monitorex.Components.CoreTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Monitorex.Components.Core

  describe "data_table/1" do
    test "renders table with columns and rows" do
      assigns = %{
        columns: [
          %{label: "Name", key: :name},
          %{label: "Status", key: :status, sortable?: true}
        ],
        rows: [
          %{name: "api.example.com", status: 200},
          %{name: "api.test.com", status: 404}
        ]
      }

      html = render_component(&Core.data_table/1, assigns)

      assert html =~ "Name"
      assert html =~ "Status"
      assert html =~ "api.example.com"
      assert html =~ "api.test.com"
      assert html =~ "200"
      assert html =~ "404"
      assert html =~ "sortable"
    end

    test "renders empty message when no rows" do
      assigns = %{
        columns: [%{label: "Name", key: :name}],
        rows: [],
        empty_message: "No hosts found"
      }

      html = render_component(&Core.data_table/1, assigns)

      assert html =~ "No hosts found"
      # There should still be a tr with the empty message
      assert html =~ "data-table-empty"
    end

    test "sets sortable class on sortable columns" do
      assigns = %{
        columns: [
          %{label: "Name", key: :name, sortable?: true},
          %{label: "Count", key: :count}
        ],
        rows: [%{name: "test", count: 1}]
      }

      html = render_component(&Core.data_table/1, assigns)

      assert html =~ "sortable"
    end

    test "adds phx-click on sortable headers" do
      assigns = %{
        columns: [
          %{label: "Name", key: :name, sortable?: true}
        ],
        rows: [%{name: "test"}]
      }

      html = render_component(&Core.data_table/1, assigns)

      assert html =~ ~s(phx-click="sort")
      assert html =~ ~s(phx-value-key="name")
    end

    test "renders sort indicator when column is active" do
      assigns = %{
        columns: [
          %{label: "Name", key: :name, sortable?: true}
        ],
        rows: [%{name: "test"}],
        sort_by: :name,
        sort_dir: "asc"
      }

      html = render_component(&Core.data_table/1, assigns)

      assert html =~ "▲"
    end
  end

  describe "summary_card/1" do
    test "renders label and value" do
      assigns = %{label: "Total Requests", value: "1,234"}

      html = render_component(&Core.summary_card/1, assigns)

      assert html =~ "Total Requests"
      assert html =~ "1,234"
    end

    test "renders up trend indicator" do
      assigns = %{label: "Errors", value: "5", trend: :up}

      html = render_component(&Core.summary_card/1, assigns)

      assert html =~ "↑"
    end

    test "renders down trend indicator" do
      assigns = %{label: "Latency", value: "42ms", trend: :down}

      html = render_component(&Core.summary_card/1, assigns)

      assert html =~ "↓"
    end

    test "does not render trend when nil" do
      assigns = %{label: "Requests", value: "100"}

      html = render_component(&Core.summary_card/1, assigns)

      refute html =~ "&#9650;"
      refute html =~ "&#9660;"
    end

    test "applies custom class" do
      assigns = %{label: "Test", value: "0", class: "custom-class"}

      html = render_component(&Core.summary_card/1, assigns)

      assert html =~ "custom-class"
    end
  end

  describe "status_badge/1" do
    test "renders 200 OK with green class" do
      assigns = %{status: 200}

      html = render_component(&Core.status_badge/1, assigns)

      assert html =~ "200 OK"
      assert html =~ "badge-success"
    end

    test "renders 404 with yellow class" do
      assigns = %{status: 404}

      html = render_component(&Core.status_badge/1, assigns)

      assert html =~ "404 Not Found"
      assert html =~ "badge-client-error"
    end

    test "renders 500 with red class" do
      assigns = %{status: 500}

      html = render_component(&Core.status_badge/1, assigns)

      assert html =~ "500 Internal Server Error"
      assert html =~ "badge-server-error"
    end

    test "renders 302 with blue class" do
      assigns = %{status: 302}

      html = render_component(&Core.status_badge/1, assigns)

      assert html =~ "302 Found"
      assert html =~ "badge-redirect"
    end

    test "renders unknown status code" do
      assigns = %{status: 999}

      html = render_component(&Core.status_badge/1, assigns)

      assert html =~ "999 Unknown"
    end

    test "renders default class for non-standard status" do
      assigns = %{status: 0}

      html = render_component(&Core.status_badge/1, assigns)

      assert html =~ "badge-default"
    end

    test "renders common status texts" do
      for {status, text} <- [
            {204, "No Content"},
            {301, "Moved Permanently"},
            {304, "Not Modified"},
            {400, "Bad Request"},
            {401, "Unauthorized"},
            {403, "Forbidden"},
            {405, "Method Not Allowed"},
            {409, "Conflict"},
            {422, "Unprocessable Entity"},
            {429, "Too Many Requests"},
            {502, "Bad Gateway"},
            {503, "Service Unavailable"},
            {504, "Gateway Timeout"}
          ] do
        html = render_component(&Core.status_badge/1, %{status: status})
        assert html =~ text
      end
    end
  end

  describe "node_selector/1" do
    test "renders select with options" do
      assigns = %{
        nodes: ["node1", "node2", "node3"],
        selected: "node2",
        event: "select_node"
      }

      html = render_component(&Core.node_selector/1, assigns)

      assert html =~ "All Nodes"
      assert html =~ "node1"
      assert html =~ "node2"
      assert html =~ "node3"
      assert html =~ ~s(phx-change="select_node")
    end

    test "marks selected option" do
      assigns = %{
        nodes: ["node1", "node2"],
        selected: "node2"
      }

      html = render_component(&Core.node_selector/1, assigns)

      assert html =~ ~s(selected)
    end

    test "uses default event name" do
      assigns = %{
        nodes: ["node1"],
        selected: ""
      }

      html = render_component(&Core.node_selector/1, assigns)

      assert html =~ ~s(phx-change="select_node")
    end
  end

  describe "metric_tile/1" do
    test "renders metric with label and value" do
      assigns = %{label: "RPS", value: "42"}
      html = render_component(&Core.metric_tile/1, assigns)

      assert html =~ "RPS"
      assert html =~ "42"
    end
  end

  describe "page_header/1" do
    test "renders title and subtitle" do
      assigns = %{title: "Overview", subtitle: "Dashboard summary"}
      html = render_component(&Core.page_header/1, assigns)

      assert html =~ "Overview"
      assert html =~ "Dashboard summary"
    end

    test "renders without subtitle" do
      assigns = %{title: "Overview"}
      html = render_component(&Core.page_header/1, assigns)

      assert html =~ "Overview"
    end
  end

  describe "pagination/1" do
    test "renders pagination controls" do
      assigns = %{current: 1, total: 5, event: "change_page"}
      html = render_component(&Core.pagination/1, assigns)

      assert html =~ "1 / 5"
      assert html =~ ~s(phx-click="change_page")
      assert html =~ "Next"
    end

    test "disables previous on first page" do
      assigns = %{current: 1, total: 3}
      html = render_component(&Core.pagination/1, assigns)

      assert html =~ "disabled"
    end

    test "disables next on last page" do
      assigns = %{current: 3, total: 3}
      html = render_component(&Core.pagination/1, assigns)

      assert html =~ "disabled"
    end

    test "renders ellipsis for large page counts" do
      assigns = %{current: 2, total: 20}
      html = render_component(&Core.pagination/1, assigns)

      assert html =~ "5"
      assert html =~ "20"

      assigns = %{current: 19, total: 20}
      html = render_component(&Core.pagination/1, assigns)

      assert html =~ "16"
      assert html =~ "20"

      assigns = %{current: 10, total: 20}
      html = render_component(&Core.pagination/1, assigns)

      assert html =~ "9"
      assert html =~ "10"
      assert html =~ "11"
    end
  end

  describe "export_button/1" do
    test "renders CSV and JSON export links" do
      assigns = %{page_name: "outbound_overview"}
      html = render_component(&Core.export_button/1, assigns)

      assert html =~ "/export/outbound_overview/csv"
      assert html =~ "/export/outbound_overview/json"
    end
  end

  describe "back_link/1" do
    test "renders back link with path" do
      assigns = %{to: "/inbound", label: "Back to inbound"}
      html = render_component(&Core.back_link/1, assigns)

      assert html =~ "/inbound"
      assert html =~ "Back to inbound"
    end
  end
end
