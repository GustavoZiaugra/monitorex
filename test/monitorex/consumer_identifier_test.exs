defmodule Monitorex.ConsumerIdentifierTest do
  use ExUnit.Case, async: true

  alias Monitorex.ConsumerIdentifier

  defp conn(headers \\ []) do
    Plug.Test.conn(:get, "/", nil)
    |> Map.put(:req_headers, headers)
  end

  describe "basic-auth username" do
    test "extracts username from valid basic auth" do
      c = conn([{"authorization", "Basic " <> Base.encode64("alice:secret123")}])
      assert ConsumerIdentifier.identify(c) == "alice"
    end

    test "handles username with colons in password" do
      c = conn([{"authorization", "Basic " <> Base.encode64("bob:pass:word:with:colons")}])
      assert ConsumerIdentifier.identify(c) == "bob"
    end

    test "returns nil when basic auth has no username" do
      c = conn([{"authorization", "Basic " <> Base.encode64(":onlypassword")}])
      assert ConsumerIdentifier.identify(c) == nil
    end

    test "returns nil for missing authorization header" do
      c = conn([])
      assert ConsumerIdentifier.identify(c) == nil
    end

    test "returns nil for non-basic auth scheme" do
      c = conn([{"authorization", "Bearer some.token.here"}])
      assert ConsumerIdentifier.identify(c) == nil
    end

    test "returns nil for malformed base64" do
      c = conn([{"authorization", "Basic not-valid-base64!!!"}])
      assert ConsumerIdentifier.identify(c) == nil
    end
  end

  describe "x-api-key header" do
    test "extracts first 8 characters of x-api-key" do
      c = conn([{"x-api-key", "sk-abcdef123456"}])
      assert ConsumerIdentifier.identify(c) == "sk-abcde"
    end

    test "handles short api keys" do
      c = conn([{"x-api-key", "short"}])
      assert ConsumerIdentifier.identify(c) == "short"
    end

    test "returns nil when x-api-key is missing" do
      c = conn([])
      assert ConsumerIdentifier.identify(c) == nil
    end
  end

  describe "priority order" do
    test "basic-auth takes priority over x-api-key" do
      c = conn([
        {"authorization", "Basic " <> Base.encode64("alice:pass")},
        {"x-api-key", "sk-abcdef123456"}
      ])
      assert ConsumerIdentifier.identify(c) == "alice"
    end
  end

  describe "custom consumer_fn config" do
    setup do
      Application.put_env(:monitorex, :consumer_fn, fn conn ->
        Plug.Conn.get_req_header(conn, "x-consumer") |> List.first()
      end)
      on_exit(fn -> Application.delete_env(:monitorex, :consumer_fn) end)
    end

    test "custom function takes highest priority" do
      c = conn([
        {"x-consumer", "custom-tenant"},
        {"authorization", "Basic " <> Base.encode64("alice:pass")}
      ])
      assert ConsumerIdentifier.identify(c) == "custom-tenant"
    end

    test "falls through when custom fn returns nil" do
      c = conn([{"authorization", "Basic " <> Base.encode64("alice:pass")}])
      assert ConsumerIdentifier.identify(c) == "alice"
    end
  end

  describe "nil fallback" do
    test "returns nil when no consumer info is present" do
      c = conn([])
      assert ConsumerIdentifier.identify(c) == nil
    end
  end
end
