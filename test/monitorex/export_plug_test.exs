defmodule Monitorex.ExportPlugTest do
  use ExUnit.Case, async: false

  alias Monitorex.ExportPlug
  alias Monitorex.LiveComponentFixtures
  alias Plug.Test

  @tables [
    :monitorex_outbound_hosts,
    :monitorex_outbound_endpoints,
    :monitorex_outbound_recent,
    :monitorex_outbound_duration_samples,
    :monitorex_inbound_routes,
    :monitorex_inbound_consumers,
    :monitorex_inbound_recent,
    :monitorex_inbound_duration_samples
  ]

  setup do
    LiveComponentFixtures.reset_ets_tables(@tables)
    :ok
  end

  defp call(page, format) do
    :get
    |> Test.conn("/export/#{page}/#{format}")
    |> Map.put(:params, %{"page" => page, "format" => format})
    |> ExportPlug.call([])
  end

  describe "CSV exports" do
    test "exports outbound_overview as CSV" do
      :ets.insert(:monitorex_outbound_hosts, {"host-a", %{requests: 10, errors: 1, total_duration: 100.0, last_seen: 1000}})

      conn = call("outbound_overview", "csv")
      assert conn.status == 200
      assert {"content-type", "text/csv; charset=utf-8"} in conn.resp_headers
      assert conn.resp_body =~ "host"
      assert conn.resp_body =~ "host-a"
    end

    test "exports inbound_overview as CSV" do
      :ets.insert(:monitorex_inbound_routes, {"GET:/api/users", %{requests: 3, errors: 0, total_duration: 30.0, last_seen: 1000}})

      conn = call("inbound_overview", "csv")
      assert conn.status == 200
      assert conn.resp_body =~ "/api/users"
    end

    test "exports inbound_consumers as CSV" do
      :ets.insert(:monitorex_inbound_consumers, {"alice", %{requests: 5, errors: 0, total_duration: 50.0, last_seen: 1000}})

      conn = call("inbound_consumers", "csv")
      assert conn.status == 200
      assert conn.resp_body =~ "alice"
    end

    test "exports timeline as CSV" do
      now = System.system_time(:microsecond)

      :ets.insert(
        :monitorex_outbound_recent,
        {now,
         %Monitorex.Event{
           source: :tesla,
           direction: :outbound,
           method: "GET",
           host: "host-a",
           path: "/x",
           status: 200,
           status_class: :success,
           duration_ms: 1.0,
           timestamp: now
         }}
      )

      conn = call("timeline", "csv")
      assert conn.status == 200
      assert conn.resp_body =~ "host-a"
    end

    test "exports route_detail as CSV" do
      :ets.insert(:monitorex_inbound_consumers, {"alice", %{requests: 5, errors: 0, total_duration: 50.0, last_seen: 1000}})

      conn = call("route_detail", "csv")
      assert conn.status == 200
      assert conn.resp_body =~ "alice"
    end
  end

  describe "JSON exports" do
    test "exports outbound_recent as JSON" do
      now = System.system_time(:microsecond)

      :ets.insert(
        :monitorex_outbound_recent,
        {now,
         %Monitorex.Event{
           source: :tesla,
           direction: :outbound,
           method: "GET",
           host: "host-a",
           path: "/x",
           status: 200,
           status_class: :success,
           duration_ms: 1.0,
           timestamp: now
         }}
      )

      conn = call("outbound_recent", "json")
      assert conn.status == 200
      assert {"content-type", "application/json; charset=utf-8"} in conn.resp_headers
      assert [%{"method" => "GET"}] = Jason.decode!(conn.resp_body)
    end

    test "exports inbound_consumers as JSON" do
      :ets.insert(:monitorex_inbound_consumers, {"alice", %{requests: 5, errors: 0, total_duration: 50.0, last_seen: 1000}})

      conn = call("inbound_consumers", "json")
      assert conn.status == 200
      assert [%{"consumer" => "alice"}] = Jason.decode!(conn.resp_body)
    end
  end

  describe "error handling" do
    test "returns 400 for invalid format" do
      conn = call("outbound_overview", "xml")
      assert conn.status == 400
    end

    test "returns 404 when no data available" do
      conn = call("outbound_overview", "csv")
      assert conn.status == 404
    end

    test "returns 404 for unsupported page" do
      conn = call("unknown_page", "csv")
      assert conn.status == 404
    end

    test "host_detail returns 404 because it has no data" do
      conn = call("host_detail", "csv")
      assert conn.status == 404
    end
  end
end
