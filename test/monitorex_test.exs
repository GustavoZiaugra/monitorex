defmodule MonitorexTest do
  use ExUnit.Case, async: true

  alias Monitorex

  describe "memory_usage/0" do
    test "returns a map with expected keys" do
      result = Monitorex.memory_usage()

      assert is_map(result.tables)
      assert is_integer(result.total_words)
      assert is_float(result.total_kb)
      assert result.total_kb >= 0
    end

    test "includes all expected tables" do
      result = Monitorex.memory_usage()

      assert Map.has_key?(result.tables, :monitorex_outbound_hosts)
      assert Map.has_key?(result.tables, :monitorex_outbound_endpoints)
      assert Map.has_key?(result.tables, :monitorex_outbound_recent)
      assert Map.has_key?(result.tables, :monitorex_inbound_routes)
      assert Map.has_key?(result.tables, :monitorex_inbound_recent)
    end

    test "per-table entries have size and memory_words" do
      result = Monitorex.memory_usage()

      Enum.each(result.tables, fn {_name, info} ->
        assert is_integer(info.size)
        assert is_integer(info.memory_words)
        assert info.size >= 0
        assert info.memory_words >= 0
      end)
    end
  end
end
