defmodule Monitorex.ApiTest do
  use ExUnit.Case, async: true

  alias Monitorex.Api
  alias Plug.Test

  describe "json_ok/3" do
    test "sends success JSON envelope" do
      conn = Test.conn(:get, "/")
      conn = Api.json_ok(conn, %{foo: "bar"})

      assert conn.status == 200
      assert {"content-type", "application/json; charset=utf-8"} in conn.resp_headers
      assert Jason.decode!(conn.resp_body) == %{"ok" => true, "data" => %{"foo" => "bar"}}
    end

    test "supports custom status and headers" do
      conn = Test.conn(:get, "/")
      conn = Api.json_ok(conn, %{}, status: 201, headers: [{"x-custom", "yes"}])

      assert conn.status == 201
      assert {"x-custom", "yes"} in conn.resp_headers
    end
  end

  describe "json_error/3" do
    test "sends error JSON envelope" do
      conn = Test.conn(:get, "/")
      conn = Api.json_error(conn, "bad request", 400)

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body) == %{"ok" => false, "error" => "bad request"}
    end

    test "defaults to status 400" do
      conn = Test.conn(:get, "/")
      conn = Api.json_error(conn, "bad request")

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body) == %{"ok" => false, "error" => "bad request"}
    end
  end

  describe "set_cors/1" do
    test "adds CORS headers" do
      conn = Test.conn(:get, "/")
      conn = Api.set_cors(conn)

      assert {"access-control-allow-origin", "*"} in conn.resp_headers
      assert {"access-control-allow-methods", "GET, OPTIONS"} in conn.resp_headers
      assert {"access-control-allow-headers", "Content-Type, Authorization"} in conn.resp_headers
      assert {"access-control-max-age", "86400"} in conn.resp_headers
    end
  end

  describe "parse_filters/1" do
    test "parses default limit and offset" do
      assert Api.parse_filters(%{}) == [limit: 50, offset: 0]
    end

    test "caps limit at 500 and minimum 1" do
      assert Api.parse_filters(%{"limit" => "1000"}) == [limit: 500, offset: 0]
      assert Api.parse_filters(%{"limit" => "0"}) == [limit: 1, offset: 0]
    end

    test "parses host, consumer, route, method filters" do
      params = %{"host" => "a.com", "consumer" => "alice", "route" => "GET:/x", "method" => "GET"}
      opts = Api.parse_filters(params)

      assert opts[:host] == "a.com"
      assert opts[:consumer] == "alice"
      assert opts[:route] == "GET:/x"
      assert opts[:method] == "GET"
    end

    test "parses status_class atom" do
      opts = Api.parse_filters(%{"status_class" => "server_error"})
      assert opts[:status_class] == :server_error
    end

    test "parses status code" do
      opts = Api.parse_filters(%{"status" => "500"})
      assert opts[:status] == 500
    end

    test "ignores invalid status" do
      opts = Api.parse_filters(%{"status" => "abc"})
      refute Keyword.has_key?(opts, :status)
    end

    test "parses ISO 8601 since into microseconds" do
      opts = Api.parse_filters(%{"since" => "2024-01-15T10:00:00Z"})
      assert opts[:since] == 1_705_312_800_000_000
    end

    test "ignores invalid since" do
      opts = Api.parse_filters(%{"since" => "not-a-date"})
      refute Keyword.has_key?(opts, :since)
    end

    test "ignores empty string values" do
      opts = Api.parse_filters(%{"host" => "", "status" => "", "since" => ""})
      assert opts == [limit: 50, offset: 0]
    end

    test "handles missing limit and offset" do
      opts = Api.parse_filters(%{"limit" => nil, "offset" => nil})
      assert opts == [limit: 50, offset: 0]
    end

    test "passes through integer limit and offset" do
      opts = Api.parse_filters(%{"limit" => 10, "offset" => 5})
      assert opts[:limit] == 10
      assert opts[:offset] == 5
    end

    test "falls back for invalid limit and offset" do
      opts = Api.parse_filters(%{"limit" => "abc", "offset" => "xyz"})
      assert opts[:limit] == 1
      assert opts[:offset] == 0
    end
  end

  describe "pagination_headers/3" do
    test "returns pagination header tuples" do
      headers = Api.pagination_headers(100, [limit: 25, offset: 10], 25)

      assert headers == [
               {"x-total-count", "100"},
               {"x-page-size", "25"},
               {"x-page-offset", "10"},
               {"x-returned-count", "25"}
             ]
    end
  end

  describe "event_to_api/1" do
    test "strips internal fields from event" do
      event = %Monitorex.Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "a.com",
        path: "/x",
        full_url: "https://a.com/x",
        status: 200,
        status_class: :success,
        duration_ms: 1.0,
        consumer: nil,
        error: nil,
        timestamp: 123,
        request_headers: [{"x", "y"}],
        response_headers: nil,
        request_body: "body",
        slow: true
      }

      api = Api.event_to_api(event)

      assert api == %{
               source: :tesla,
               direction: :outbound,
               method: "GET",
               host: "a.com",
               path: "/x",
               full_url: "https://a.com/x",
               status: 200,
               status_class: :success,
               duration_ms: 1.0,
               consumer: nil,
               error: nil,
               timestamp: 123
             }
    end
  end

  describe "error_rate/1" do
    test "returns nil for nil" do
      assert Api.error_rate(nil) == nil
    end

    test "returns number values" do
      assert Api.error_rate(0.5) == 0.5
      assert Api.error_rate(10) == 10
    end

    test "returns nil for invalid values" do
      assert Api.error_rate("high") == nil
    end
  end
end
