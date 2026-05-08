defmodule Monitorex.URLRedactorTest do
  use ExUnit.Case, async: true

  alias Monitorex.URLRedactor

  describe "default denylist" do
    test "redacts 'key' parameter" do
      assert URLRedactor.redact("https://api.stripe.com/v1/charges?key=sk_live_xxx") ==
               "https://api.stripe.com/v1/charges?key=%5BREDACTED%5D"
    end

    test "redacts 'token' parameter" do
      assert URLRedactor.redact("https://api.example.com/data?token=abc123def456") ==
               "https://api.example.com/data?token=%5BREDACTED%5D"
    end

    test "redacts 'api_key' parameter" do
      assert URLRedactor.redact("https://api.example.com/v1?api_key=my-secret-key") ==
               "https://api.example.com/v1?api_key=%5BREDACTED%5D"
    end

    test "redacts 'apikey' parameter" do
      assert URLRedactor.redact("https://api.example.com/v1?apikey=abc123") ==
               "https://api.example.com/v1?apikey=%5BREDACTED%5D"
    end

    test "redacts 'secret' parameter" do
      assert URLRedactor.redact("https://api.example.com/v1?secret=sup3rs3cr3t") ==
               "https://api.example.com/v1?secret=%5BREDACTED%5D"
    end

    test "redacts 'password' parameter" do
      assert URLRedactor.redact("https://api.example.com/login?password=hunter2") ==
               "https://api.example.com/login?password=%5BREDACTED%5D"
    end

    test "redacts 'auth' parameter" do
      assert URLRedactor.redact("https://api.example.com/v1?auth=bearer_token") ==
               "https://api.example.com/v1?auth=%5BREDACTED%5D"
    end

    test "redacts 'access_token' parameter" do
      assert URLRedactor.redact("https://api.example.com/v1?access_token=ghp_xxxxx") ==
               "https://api.example.com/v1?access_token=%5BREDACTED%5D"
    end

    test "redacts 'refresh_token' parameter" do
      assert URLRedactor.redact("https://api.example.com/v1?refresh_token=rt_xxxxx") ==
               "https://api.example.com/v1?refresh_token=%5BREDACTED%5D"
    end
  end

  describe "non-sensitive parameters" do
    test "preserves non-sensitive params" do
      assert URLRedactor.redact("https://api.example.com/users?page=1&per_page=20&sort=name") ==
               "https://api.example.com/users?page=1&per_page=20&sort=name"
    end

    test "redacts only sensitive params, preserves others" do
      assert URLRedactor.redact(
               "https://api.example.com/v1?key=secret&page=1&token=abc&sort=desc"
             ) ==
               "https://api.example.com/v1?key=%5BREDACTED%5D&page=1&token=%5BREDACTED%5D&sort=desc"
    end
  end

  describe "edge cases" do
    test "handles URLs with no query string" do
      assert URLRedactor.redact("https://api.example.com/health") ==
               "https://api.example.com/health"
    end

    test "handles nil" do
      assert URLRedactor.redact(nil) == nil
    end

    test "handles empty string" do
      assert URLRedactor.redact("") == ""
    end

    test "handles empty query string" do
      assert URLRedactor.redact("https://api.example.com/health?") ==
               "https://api.example.com/health?"
    end

    test "handles mixed case param names (exact match only)" do
      assert URLRedactor.redact("https://api.example.com?Key=value&API_KEY=value") ==
               "https://api.example.com?Key=value&API_KEY=value"
    end
  end

  describe "custom config" do
    setup do
      Application.put_env(:monitorex, :sensitive_query_params, ["custom_secret"])
      on_exit(fn -> Application.delete_env(:monitorex, :sensitive_query_params) end)
    end

    test "respects custom sensitive param names from config" do
      assert URLRedactor.redact("https://api.example.com/v1?custom_secret=xxx&page=1") ==
               "https://api.example.com/v1?custom_secret=%5BREDACTED%5D&page=1"
    end

    test "does not use defaults when custom config is set" do
      assert URLRedactor.redact("https://api.example.com/v1?key=should_not_be_redacted") ==
               "https://api.example.com/v1?key=should_not_be_redacted"
    end
  end
end
