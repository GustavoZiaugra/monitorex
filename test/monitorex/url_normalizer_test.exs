defmodule Monitorex.UrlNormalizerTest do
  use ExUnit.Case, async: true

  alias Monitorex.UrlNormalizer

  describe "normalize/1" do
    test "normalizes UUIDs to :uuid" do
      assert UrlNormalizer.normalize(
               "https://api.example.com/users/550e8400-e29b-41d4-a716-446655440000"
             ) ==
               "https://api.example.com/users/:uuid"
    end

    test "normalizes numeric segments to :id" do
      assert UrlNormalizer.normalize("https://api.example.com/users/12345") ==
               "https://api.example.com/users/:id"
    end

    test "normalizes long hex strings to :hex_id" do
      assert UrlNormalizer.normalize("https://api.example.com/v2/abc123def4567890") ==
               "https://api.example.com/v2/:hex_id"
    end

    test "normalizes long tokens to :token" do
      assert UrlNormalizer.normalize("https://api.example.com/assets/a1b2c3d4e5f6_token") ==
               "https://api.example.com/assets/:token"
    end

    test "handles mixed paths with multiple dynamic segments" do
      assert UrlNormalizer.normalize(
               "https://api.example.com/users/123/orders/550e8400-e29b-41d4-a716-446655440000"
             ) ==
               "https://api.example.com/users/:id/orders/:uuid"
    end

    test "preserves static paths unchanged" do
      assert UrlNormalizer.normalize("https://api.example.com/api/v1/health") ==
               "https://api.example.com/api/v1/health"
    end

    test "handles nil gracefully" do
      assert UrlNormalizer.normalize(nil) == nil
    end

    test "handles empty string gracefully" do
      assert UrlNormalizer.normalize("") == ""
    end

    test "normalization is idempotent" do
      url = "https://api.example.com/users/abc-123-def"
      assert UrlNormalizer.normalize(UrlNormalizer.normalize(url)) == UrlNormalizer.normalize(url)
    end
  end

  describe "normalize/2 with cardinality cap" do
    test "returns normalized path when under the limit" do
      tracked = MapSet.new([{"api.example.com", "/users/:id"}])

      assert UrlNormalizer.normalize("https://api.example.com/orders/123", tracked) ==
               "https://api.example.com/orders/:id"
    end

    test "returns /:other when exceeding cardinality limit" do
      # Temporarily lower the limit
      Application.put_env(:monitorex, :max_endpoints_per_host, 2)

      tracked =
        MapSet.new([
          {"api.example.com", "/users/:id"},
          {"api.example.com", "/orders/:id"}
        ])

      assert UrlNormalizer.normalize("https://api.example.com/items/456", tracked) ==
               "https://api.example.com/:other"

      # Cleanup
      Application.delete_env(:monitorex, :max_endpoints_per_host)
    end
  end

  describe "normalize_segment/2 with custom patterns" do
    test "matches user-defined patterns" do
      patterns = [{~r/\A[A-Z]{2}\d{4}\z/, ":product_code"}]
      assert UrlNormalizer.normalize_segment("AB1234", patterns) == ":product_code"
    end

    test "custom patterns have higher priority than heuristics" do
      patterns = [{~r/\A\d+\z/, ":numeric_custom"}]
      assert UrlNormalizer.normalize_segment("999", patterns) == ":numeric_custom"
    end
  end
end
