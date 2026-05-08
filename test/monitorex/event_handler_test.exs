defmodule Monitorex.EventHandlerTest do
  use ExUnit.Case, async: true

  alias Monitorex.Event
  alias Monitorex.EventHandler

  # ── Event struct and helper functions ──

  describe "Event struct" do
    test "has all expected fields" do
      event = %Event{}
      assert Map.has_key?(event, :source)
      assert Map.has_key?(event, :direction)
      assert Map.has_key?(event, :method)
      assert Map.has_key?(event, :host)
      assert Map.has_key?(event, :path)
      assert Map.has_key?(event, :full_url)
      assert Map.has_key?(event, :status)
      assert Map.has_key?(event, :status_class)
      assert Map.has_key?(event, :duration_ms)
      assert Map.has_key?(event, :consumer)
      assert Map.has_key?(event, :error)
      assert Map.has_key?(event, :timestamp)
      assert Map.has_key?(event, :dedup_key)
    end
  end

  describe "classify_status/1" do
    test "classifies 2xx as :success" do
      assert Event.classify_status(200) == :success
      assert Event.classify_status(201) == :success
      assert Event.classify_status(204) == :success
    end

    test "classifies 3xx as :redirect" do
      assert Event.classify_status(301) == :redirect
      assert Event.classify_status(302) == :redirect
      assert Event.classify_status(304) == :redirect
    end

    test "classifies 4xx as :client_error" do
      assert Event.classify_status(400) == :client_error
      assert Event.classify_status(404) == :client_error
      assert Event.classify_status(429) == :client_error
    end

    test "classifies 5xx as :server_error" do
      assert Event.classify_status(500) == :server_error
      assert Event.classify_status(502) == :server_error
      assert Event.classify_status(503) == :server_error
    end
  end

  describe "duration_ms/1" do
    test "converts native time to milliseconds" do
      ms = Event.duration_ms(1_000_000)
      assert is_float(ms)
      assert_in_delta ms, 1.0, 0.01
    end

    test "returns 0.0 for zero duration" do
      assert Event.duration_ms(0) == 0.0
    end

    test "handles fractional milliseconds" do
      ms = Event.duration_ms(500)
      assert is_float(ms)
      assert ms < 1.0
    end
  end

  describe "normalize_method/1" do
    test "converts atom :get to \"GET\"" do
      assert Event.normalize_method(:get) == "GET"
    end

    test "converts atom :post to \"POST\"" do
      assert Event.normalize_method(:post) == "POST"
    end

    test "converts atom :put to \"PUT\"" do
      assert Event.normalize_method(:put) == "PUT"
    end

    test "converts atom :delete to \"DELETE\"" do
      assert Event.normalize_method(:delete) == "DELETE"
    end

    test "handles already-uppercase strings" do
      assert Event.normalize_method("GET") == "GET"
    end

    test "handles lowercase strings" do
      assert Event.normalize_method("get") == "GET"
    end
  end

  describe "extract_host/1" do
    test "extracts host from URI struct" do
      uri = %URI{scheme: "https", host: "api.example.com", path: "/v1/test"}
      assert Event.extract_host(uri) == "api.example.com"
    end

    test "extracts host from URL string" do
      assert Event.extract_host("https://api.example.com/v1/test") == "api.example.com"
    end

    test "extracts host from URL string with port" do
      assert Event.extract_host("http://localhost:4000/health") == "localhost"
    end

    test "returns nil for URI with no host" do
      assert Event.extract_host(%URI{path: "/local"}) == nil
    end
  end

  # ── Tesla handler ──

  describe "handle_tesla_event/4" do
    test "parses Tesla telemetry into Event" do
      url = %URI{scheme: "https", host: "api.example.com", path: "/users/123", query: nil}
      pid = self()
      mono = System.monotonic_time()

      metadata = %{
        url: url,
        method: :get,
        status: 200,
        pid: pid,
        monotonic_time: mono
      }

      measurements = %{
        duration: 1_000_000
      }

      event =
        EventHandler.handle_tesla_event(
          [:tesla, :request, :stop],
          measurements,
          metadata,
          []
        )

      assert event.source == :tesla
      assert event.direction == :outbound
      assert event.method == "GET"
      assert event.host == "api.example.com"
      assert event.path == "/users/:id"
      assert String.contains?(event.full_url, "/users/:id")
      assert event.status == 200
      assert event.status_class == :success
      assert is_float(event.duration_ms)
      assert_in_delta event.duration_ms, 1.0, 0.01
      assert event.dedup_key == {pid, mono}
      assert event.timestamp == mono
    end

    test "handles error status codes" do
      url = %URI{scheme: "https", host: "api.example.com", path: "/error", query: nil}

      metadata = %{
        url: url,
        method: :post,
        status: 500,
        pid: self(),
        monotonic_time: System.monotonic_time()
      }

      measurements = %{duration: 500_000}

      event =
        EventHandler.handle_tesla_event(
          [:tesla, :request, :stop],
          measurements,
          metadata,
          []
        )

      assert event.status == 500
      assert event.status_class == :server_error
      assert event.method == "POST"
    end

    test "redacts sensitive query parameters" do
      url = %URI{
        scheme: "https",
        host: "api.example.com",
        path: "/data",
        query: "key=sk_live_secret&page=1"
      }

      metadata = %{
        url: url,
        method: :get,
        status: 200,
        pid: self(),
        monotonic_time: System.monotonic_time()
      }

      measurements = %{duration: 100_000}

      event =
        EventHandler.handle_tesla_event(
          [:tesla, :request, :stop],
          measurements,
          metadata,
          []
        )

      assert String.contains?(event.full_url, "page=1")
      assert String.contains?(event.full_url, "key=%5BREDACTED%5D") or
               String.contains?(event.full_url, "key=[REDACTED]")
    end

    test "redacts request and response headers" do
      url = %URI{scheme: "https", host: "api.example.com", path: "/data"}

      metadata = %{
        url: url,
        method: :get,
        status: 200,
        pid: self(),
        monotonic_time: System.monotonic_time(),
        req_headers: [{"authorization", "Bearer secret"}, {"accept", "application/json"}],
        resp_headers: [{"set-cookie", "session=abc"}, {"content-type", "application/json"}]
      }

      measurements = %{duration: 100_000}

      event =
        EventHandler.handle_tesla_event(
          [:tesla, :request, :stop],
          measurements,
          metadata,
          []
        )

      assert event.request_headers == [
               {"authorization", "••••redacted••••"},
               {"accept", "application/json"}
             ]

      assert event.response_headers == [
               {"set-cookie", "••••redacted••••"},
               {"content-type", "application/json"}
             ]
    end

    test "stores request and response bodies when enabled" do
      Application.put_env(:monitorex, :store_request_body, true)
      Application.put_env(:monitorex, :store_response_body, true)

      url = %URI{scheme: "https", host: "api.example.com", path: "/data"}

      metadata = %{
        url: url,
        method: :get,
        status: 200,
        pid: self(),
        monotonic_time: System.monotonic_time(),
        request_body: "req",
        response_body: "resp"
      }

      measurements = %{duration: 100_000}

      event =
        EventHandler.handle_tesla_event(
          [:tesla, :request, :stop],
          measurements,
          metadata,
          []
        )

      assert event.request_body == "req"
      assert event.response_body == "resp"

      Application.delete_env(:monitorex, :store_request_body)
      Application.delete_env(:monitorex, :store_response_body)
    end

    test "does not store bodies when disabled" do
      Application.put_env(:monitorex, :store_request_body, false)
      Application.put_env(:monitorex, :store_response_body, false)

      url = %URI{scheme: "https", host: "api.example.com", path: "/data"}

      metadata = %{
        url: url,
        method: :get,
        status: 200,
        pid: self(),
        monotonic_time: System.monotonic_time(),
        request_body: "req",
        response_body: "resp"
      }

      measurements = %{duration: 100_000}

      event =
        EventHandler.handle_tesla_event(
          [:tesla, :request, :stop],
          measurements,
          metadata,
          []
        )

      assert event.request_body == nil
      assert event.response_body == nil

      Application.delete_env(:monitorex, :store_request_body)
      Application.delete_env(:monitorex, :store_response_body)
    end
  end

  # ── Finch handler (legacy format) ──

  describe "handle_finch_event/4 — legacy format" do
    test "parses Finch telemetry with URI url into Event" do
      url = %URI{scheme: "https", host: "finch.example.com", path: "/v2/resource"}
      pid = self()
      mono = System.monotonic_time()

      metadata = %{
        url: url,
        method: :get,
        status: 200,
        pid: pid,
        monotonic_time: mono
      }

      measurements = %{duration: 2_000_000}

      event =
        EventHandler.handle_finch_event(
          [:finch, :request, :stop],
          measurements,
          metadata,
          []
        )

      assert event.source == :finch
      assert event.direction == :outbound
      assert event.method == "GET"
      assert event.host == "finch.example.com"
      assert event.path == "/v2/resource"
      assert event.status == 200
      assert event.status_class == :success
      assert event.dedup_key == {pid, mono}
    end

    test "parses Finch telemetry with string url into Event" do
      metadata = %{
        url: "https://finch.example.com/v2/resource/",
        method: "POST",
        status: 201,
        pid: self(),
        monotonic_time: System.monotonic_time()
      }

      measurements = %{duration: 1_500_000}

      event =
        EventHandler.handle_finch_event(
          [:finch, :request, :stop],
          measurements,
          metadata,
          []
        )

      assert event.source == :finch
      assert event.method == "POST"
      assert event.host == "finch.example.com"
      assert event.status == 201
      assert event.status_class == :success
    end

    test "handles string method" do
      metadata = %{
        url: %URI{scheme: "https", host: "finch.example.com", path: "/test"},
        method: "get",
        status: 200,
        pid: self(),
        monotonic_time: System.monotonic_time()
      }

      measurements = %{duration: 100_000}

      event =
        EventHandler.handle_finch_event(
          [:finch, :request, :stop],
          measurements,
          metadata,
          []
        )

      assert event.method == "GET"
    end

    test "redacts sensitive query params in Finch events" do
      metadata = %{
        url: "https://finch.example.com/auth?token=s3cr3t",
        method: :post,
        status: 200,
        pid: self(),
        monotonic_time: System.monotonic_time()
      }

      measurements = %{duration: 500_000}

      event =
        EventHandler.handle_finch_event(
          [:finch, :request, :stop],
          measurements,
          metadata,
          []
        )

      assert String.contains?(event.full_url, "token=%5BREDACTED%5D") or
               String.contains?(event.full_url, "token=[REDACTED]")
    end

    test "redacts request and response headers" do
      metadata = %{
        url: %URI{scheme: "https", host: "finch.example.com", path: "/test"},
        method: :get,
        status: 200,
        pid: self(),
        monotonic_time: System.monotonic_time(),
        req_headers: [{"x-api-key", "secret"}, {"accept", "application/json"}],
        resp_headers: [{"authorization", "Bearer token"}]
      }

      measurements = %{duration: 100_000}

      event =
        EventHandler.handle_finch_event(
          [:finch, :request, :stop],
          measurements,
          metadata,
          []
        )

      assert event.request_headers == [
               {"x-api-key", "••••redacted••••"},
               {"accept", "application/json"}
             ]

      assert event.response_headers == [{"authorization", "••••redacted••••"}]
    end
  end

  # ── Finch handler (new format — Finch.Request struct) ──

  describe "handle_finch_event/4 — new format (Finch.Request)" do
    test "parses new Finch telemetry format with Finch.Request" do
      request = %{
        scheme: :https,
        host: "jsonplaceholder.typicode.com",
        port: 443,
        method: "GET",
        path: "/posts/1",
        headers: [{"accept", "application/json"}],
        body: nil,
        query: nil,
        unix_socket: nil,
        private: %{}
      }

      metadata = %{
        name: :test_pool,
        request: request,
        result: {:ok, %{status: 200, body: "[]", headers: [{"content-type", "application/json"}]}}
      }

      measurements = %{duration: 2_500_000}

      event =
        EventHandler.handle_finch_event(
          [:finch, :request, :stop],
          measurements,
          metadata,
          []
        )

      assert event.source == :finch
      assert event.direction == :outbound
      assert event.method == "GET"
      assert event.host == "jsonplaceholder.typicode.com"
      assert event.path == "/posts/1"
      assert event.status == 200
      assert event.status_class == :success
      assert event.request_headers == [{"accept", "application/json"}]
    end

    test "handles new Finch format with monotonic_time in measurements" do
      request = %{
        scheme: :https, host: "httpbin.org", port: 443,
        method: "POST", path: "/anything", headers: [],
        body: ~S({"key":"value"}), query: nil
      }

      metadata = %{
        name: :test_pool,
        request: request,
        result: {:ok, %{status: 201, body: "{}", headers: []}}
      }

      measurements = %{duration: 500_000, monotonic_time: System.monotonic_time()}

      event =
        EventHandler.handle_finch_event(
          [:finch, :request, :stop],
          measurements,
          metadata,
          []
        )

      assert event.method == "POST"
      assert event.status == 201
      assert event.status_class == :success
      assert is_integer(event.timestamp)
    end

    test "handles new Finch format exception event" do
      request = %{
        scheme: :https, host: "bad.example.com", port: 443,
        method: "GET", path: "/fail", headers: [], body: nil, query: nil
      }

      metadata = %{
        name: :test_pool,
        request: request,
        result: {:error, :timeout}
      }

      measurements = %{duration: 10_000_000}

      event =
        EventHandler.handle_finch_event(
          [:finch, :request, :exception],
          measurements,
          metadata,
          []
        )

      assert event.source == :finch
      assert event.direction == :outbound
      assert event.status == nil
      assert event.status_class == :server_error
      assert event.error != nil
    end

    test "new format with query string builds full URL" do
      request = %{
        scheme: :https, host: "api.example.com", port: 443,
        method: "GET", path: "/search", headers: [], body: nil,
        query: "q=hello&page=1"
      }

      metadata = %{
        name: :test_pool,
        request: request,
        result: {:ok, %{status: 200, body: "[]", headers: []}}
      }

      measurements = %{duration: 100_000}

      event =
        EventHandler.handle_finch_event(
          [:finch, :request, :stop],
          measurements,
          metadata,
          []
        )

      assert event.full_url =~ "q=hello"
      assert event.full_url =~ "page=1"
    end
  end

  # ── Phoenix handler ──

  describe "handle_phoenix_event/4" do
    test "parses Phoenix telemetry into Event" do
      conn =
        Plug.Test.conn(:get, "/api/v1/users", nil)
        |> Map.put(:status, 200)
        |> Map.put(:host, "example.com")

      mono = System.monotonic_time()

      metadata = %{
        conn: conn,
        monotonic_time: mono
      }

      measurements = %{duration: 3_000_000}

      event =
        EventHandler.handle_phoenix_event(
          [:phoenix, :router_dispatch, :stop],
          measurements,
          metadata,
          []
        )

      assert event.source == :phoenix
      assert event.direction == :inbound
      assert event.method == "GET"
      assert event.host == "example.com"
      assert event.path == "/api/v1/users"
      assert event.status == 200
      assert event.status_class == :success
      assert is_float(event.duration_ms)
      assert_in_delta event.duration_ms, 3.0, 0.01
      assert event.consumer == nil
    end

    test "accepts path when inbound_path_prefixes matches" do
      Application.put_env(:monitorex, :inbound_path_prefixes, ["/api"])

      conn =
        Plug.Test.conn(:get, "/api/v1/products", nil)
        |> Map.put(:status, 200)
        |> Map.put(:host, "example.com")

      metadata = %{conn: conn}
      measurements = %{duration: 1_000_000}

      event =
        EventHandler.handle_phoenix_event(
          [:phoenix, :router_dispatch, :stop],
          measurements,
          metadata,
          []
        )

      assert event != nil
      assert event.path == "/api/v1/products"

      Application.delete_env(:monitorex, :inbound_path_prefixes)
    end

    test "filters path when inbound_path_prefixes does not match" do
      Application.put_env(:monitorex, :inbound_path_prefixes, ["/api"])

      conn =
        Plug.Test.conn(:get, "/health", nil)
        |> Map.put(:status, 200)
        |> Map.put(:host, "example.com")

      metadata = %{conn: conn}
      measurements = %{duration: 1_000_000}

      event =
        EventHandler.handle_phoenix_event(
          [:phoenix, :router_dispatch, :stop],
          measurements,
          metadata,
          []
        )

      assert event == nil

      Application.delete_env(:monitorex, :inbound_path_prefixes)
    end

    test "allows all paths when inbound_path_prefixes is not configured" do
      Application.delete_env(:monitorex, :inbound_path_prefixes)

      conn =
        Plug.Test.conn(:get, "/health", nil)
        |> Map.put(:status, 200)
        |> Map.put(:host, "example.com")

      metadata = %{conn: conn}
      measurements = %{duration: 1_000_000}

      event =
        EventHandler.handle_phoenix_event(
          [:phoenix, :router_dispatch, :stop],
          measurements,
          metadata,
          []
        )

      assert event != nil
      assert event.path == "/health"
    end

    test "extracts consumer from conn when available" do
      conn =
        Plug.Test.conn(:get, "/api/v1/orders", nil)
        |> Map.put(:status, 200)
        |> Map.put(:host, "example.com")
        |> Map.put(:req_headers, [{"authorization", "Basic " <> Base.encode64("alice:pass")}])

      metadata = %{conn: conn}
      measurements = %{duration: 2_000_000}

      event =
        EventHandler.handle_phoenix_event(
          [:phoenix, :router_dispatch, :stop],
          measurements,
          metadata,
          []
        )

      assert event != nil
      assert event.consumer == "alice"
    end

    test "redacts request and response headers from conn" do
      conn =
        Plug.Test.conn(:get, "/api/v1/orders", nil)
        |> Map.put(:status, 200)
        |> Map.put(:host, "example.com")
        |> Map.put(:req_headers, [{"authorization", "Bearer secret"}, {"accept", "application/json"}])
        |> Map.put(:resp_headers, [{"set-cookie", "session=abc"}, {"content-type", "application/json"}])

      metadata = %{conn: conn}
      measurements = %{duration: 1_000_000}

      event =
        EventHandler.handle_phoenix_event(
          [:phoenix, :router_dispatch, :stop],
          measurements,
          metadata,
          []
        )

      assert event.request_headers == [
               {"authorization", "••••redacted••••"},
               {"accept", "application/json"}
             ]

      assert event.response_headers == [
               {"set-cookie", "••••redacted••••"},
               {"content-type", "application/json"}
             ]
    end

    test "stores request and response bodies from metadata when enabled" do
      Application.put_env(:monitorex, :store_request_body, true)
      Application.put_env(:monitorex, :store_response_body, true)

      conn =
        Plug.Test.conn(:post, "/api/v1/orders", nil)
        |> Map.put(:status, 201)
        |> Map.put(:host, "example.com")

      metadata = %{conn: conn, request_body: ~S({"id":1}), response_body: ~S({"ok":true})}
      measurements = %{duration: 1_000_000}

      event =
        EventHandler.handle_phoenix_event(
          [:phoenix, :router_dispatch, :stop],
          measurements,
          metadata,
          []
        )

      assert event.request_body == ~S({"id":1})
      assert event.response_body == ~S({"ok":true})

      Application.delete_env(:monitorex, :store_request_body)
      Application.delete_env(:monitorex, :store_response_body)
    end

    test "handles error status codes in Phoenix events" do
      conn =
        Plug.Test.conn(:get, "/api/v1/items", nil)
        |> Map.put(:status, 500)
        |> Map.put(:host, "example.com")

      metadata = %{conn: conn}
      measurements = %{duration: 500_000}

      event =
        EventHandler.handle_phoenix_event(
          [:phoenix, :router_dispatch, :stop],
          measurements,
          metadata,
          []
        )

      assert event.status == 500
      assert event.status_class == :server_error
    end
  end
end
