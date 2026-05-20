defmodule Monitorex.HealthTest do
  use ExUnit.Case, async: false

  alias Monitorex.Health

  describe "check/0" do
    test "returns a map with all expected keys" do
      result = Health.check()

      assert result.status in [:healthy, :degraded]
      assert is_boolean(result.collector_alive)
      assert is_integer(result.message_queue_len)
      assert is_integer(result.uptime_seconds)
      assert is_map(result.ets_table_sizes)
      assert is_integer(result.total_ets_memory_words)
      assert is_integer(result.checked_at)
    end

    test "ets_table_sizes has all 11 tables" do
      sizes = Health.ets_table_sizes()
      assert map_size(sizes) == 11
      assert is_integer(sizes[:monitorex_outbound_hosts])
      assert is_integer(sizes[:monitorex_inbound_recent])
      assert is_integer(sizes[:monitorex_slow_outbound])
      assert is_integer(sizes[:monitorex_slow_inbound])
    end

    test "status is :healthy when collector is running and msg queue is low" do
      Application.put_env(:monitorex, :sources, [])
      Application.put_env(:monitorex, :clients, [])

      # Collector is started by the Application — so it should be alive
      result = Health.check()

      assert result.status == :healthy
      assert result.collector_alive == true

      Application.delete_env(:monitorex, :sources)
      Application.delete_env(:monitorex, :clients)
    end

    test "collector_alive is true when Application is running" do
      result = Health.check()
      assert result.collector_alive == true
    end

    test "returns integer uptime when collector is running" do
      result = Health.check()
      assert is_integer(result.uptime_seconds)
      assert result.uptime_seconds >= 0
    end
  end
end
