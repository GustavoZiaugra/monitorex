defmodule Monitorex.Components.Live.HelpersTest do
  use ExUnit.Case, async: true

  alias Monitorex.Components.Live.Helpers

  describe "format_timestamp/1" do
    test "returns '-' for nil" do
      assert Helpers.format_timestamp(nil) == "-"
    end

    test "formats valid Unix microsecond timestamp" do
      # 2024-01-01 00:00:00 UTC
      ts = DateTime.to_unix(~U[2024-01-01 00:00:00Z], :microsecond)
      assert Helpers.format_timestamp(ts) == "00:00:00"
    end

    test "returns fallback for invalid timestamp" do
      assert Helpers.format_timestamp("not_a_number") == "-"
    end
  end

  describe "status_chip_class/2" do
    test "returns active-2xx when current matches" do
      assert Helpers.status_chip_class("2xx", "2xx") == "filter-chip active-2xx"
    end

    test "returns active-3xx when current matches" do
      assert Helpers.status_chip_class("3xx", "3xx") == "filter-chip active-3xx"
    end

    test "returns active-4xx when current matches" do
      assert Helpers.status_chip_class("4xx", "4xx") == "filter-chip active-4xx"
    end

    test "returns active-5xx when current matches" do
      assert Helpers.status_chip_class("5xx", "5xx") == "filter-chip active-5xx"
    end

    test "returns active for unknown value when current matches" do
      assert Helpers.status_chip_class("other", "other") == "filter-chip active"
    end

    test "returns base class when value does not match current" do
      assert Helpers.status_chip_class("2xx", "") == "filter-chip"
      assert Helpers.status_chip_class("2xx", "4xx") == "filter-chip"
    end
  end
end
