defmodule Monitorex.EventTest do
  use ExUnit.Case, async: true

  alias Monitorex.Event

  describe "struct" do
    test "can be created with all fields" do
      event = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "api.example.com",
        path: "/users",
        status: 200,
        status_class: :success,
        duration_ms: 42.0,
        timestamp: 1_000_000
      }

      assert event.source == :tesla
      assert event.direction == :outbound
      assert event.host == "api.example.com"
    end

    test "can be created with minimal fields" do
      event = %Event{}
      assert event.source == nil
      assert event.direction == nil
    end
  end

  describe "classify_status/1" do
    test "classifies 2xx as :success" do
      assert Event.classify_status(200) == :success
      assert Event.classify_status(201) == :success
      assert Event.classify_status(299) == :success
    end

    test "classifies 3xx as :redirect" do
      assert Event.classify_status(301) == :redirect
      assert Event.classify_status(302) == :redirect
      assert Event.classify_status(304) == :redirect
    end

    test "classifies 4xx as :client_error" do
      assert Event.classify_status(400) == :client_error
      assert Event.classify_status(404) == :client_error
      assert Event.classify_status(422) == :client_error
    end

    test "classifies 5xx as :server_error" do
      assert Event.classify_status(500) == :server_error
      assert Event.classify_status(502) == :server_error
      assert Event.classify_status(503) == :server_error
    end
  end

  describe "normalize_method/1" do
    test "converts atom to uppercase string" do
      assert Event.normalize_method(:get) == "GET"
      assert Event.normalize_method(:post) == "POST"
      assert Event.normalize_method(:put) == "PUT"
      assert Event.normalize_method(:delete) == "DELETE"
    end

    test "upcases binary method" do
      assert Event.normalize_method("get") == "GET"
      assert Event.normalize_method("POST") == "POST"
    end
  end

  describe "extract_host/1" do
    test "extracts host from URI struct" do
      assert Event.extract_host(%URI{host: "api.example.com"}) == "api.example.com"
    end

    test "extracts host from URL string" do
      assert Event.extract_host("https://api.example.com/path") == "api.example.com"
      assert Event.extract_host("http://localhost:4000/health") == "localhost"
    end

    test "returns nil for URI without host" do
      assert Event.extract_host(%URI{host: nil}) == nil
    end

    test "returns nil for invalid URL" do
      assert Event.extract_host("not-a-url") == nil
    end
  end

  describe "duration_ms/1" do
    test "converts native time to milliseconds" do
      native_per_ms = System.convert_time_unit(1, :millisecond, :native)
      assert Event.duration_ms(native_per_ms) == 1.0
      assert Event.duration_ms(0) == 0.0
    end
  end
end
