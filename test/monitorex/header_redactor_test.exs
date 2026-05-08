defmodule Monitorex.HeaderRedactorTest do
  use ExUnit.Case, async: true

  alias Monitorex.HeaderRedactor

  describe "default_redacted_headers/0" do
    test "returns the built-in sensitive header list" do
      assert HeaderRedactor.default_redacted_headers() == [
               "authorization",
               "cookie",
               "set-cookie",
               "x-api-key",
               "x-auth-token"
             ]
    end
  end

  describe "redact_headers/2" do
    test "redacts matching header values case-insensitively" do
      headers = [
        {"Authorization", "Bearer secret"},
        {"content-type", "application/json"},
        {"X-API-KEY", "super-secret"}
      ]

      redacted = HeaderRedactor.redact_headers(headers, ["authorization", "x-api-key"])

      assert {"Authorization", "••••redacted••••"} in redacted
      assert {"content-type", "application/json"} in redacted
      assert {"X-API-KEY", "••••redacted••••"} in redacted
    end

    test "returns empty list for empty input" do
      assert HeaderRedactor.redact_headers([], ["authorization"]) == []
    end

    test "leaves non-matching headers untouched" do
      headers = [{"accept", "application/json"}]
      assert HeaderRedactor.redact_headers(headers, ["authorization"]) == headers
    end

    test "handles atom header names" do
      headers = [
        {:authorization, "Bearer secret"},
        {:accept, "application/json"}
      ]

      redacted = HeaderRedactor.redact_headers(headers, ["authorization"])

      assert {:authorization, "••••redacted••••"} in redacted
      assert {:accept, "application/json"} in redacted
    end
  end

  describe "redact_headers/1" do
    test "uses application config when available" do
      Application.put_env(:monitorex, :redacted_headers, ["x-custom-secret"])

      headers = [
        {"x-custom-secret", "hidden"},
        {"authorization", "Bearer visible"}
      ]

      redacted = HeaderRedactor.redact_headers(headers)

      assert {"x-custom-secret", "••••redacted••••"} in redacted
      assert {"authorization", "Bearer visible"} in redacted

      Application.delete_env(:monitorex, :redacted_headers)
    end

    test "falls back to default list when config is absent" do
      Application.delete_env(:monitorex, :redacted_headers)

      headers = [
        {"cookie", "session=abc"},
        {"accept", "application/json"}
      ]

      redacted = HeaderRedactor.redact_headers(headers)

      assert {"cookie", "••••redacted••••"} in redacted
      assert {"accept", "application/json"} in redacted
    end
  end
end
