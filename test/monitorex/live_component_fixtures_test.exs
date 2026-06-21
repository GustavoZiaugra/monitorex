defmodule Monitorex.LiveComponentFixturesTest do
  use ExUnit.Case, async: false

  alias Monitorex.LiveComponentFixtures

  test "reset_ets_tables/0 creates all tables with correct types" do
    LiveComponentFixtures.reset_ets_tables()

    for table <- [
          :monitorex_outbound_hosts,
          :monitorex_outbound_endpoints,
          :monitorex_outbound_recent,
          :monitorex_outbound_duration_samples,
          :monitorex_inbound_routes,
          :monitorex_inbound_consumers,
          :monitorex_inbound_recent,
          :monitorex_inbound_duration_samples,
          :monitorex_slow_outbound,
          :monitorex_slow_inbound,
          :monitorex_dedup
        ] do
      info = :ets.info(table)
      assert info[:name] == table
      assert info[:named_table] == true
    end
  end

  test "table types match production" do
    LiveComponentFixtures.reset_ets_tables()

    assert :ets.info(:monitorex_outbound_hosts)[:type] == :set
    assert :ets.info(:monitorex_outbound_endpoints)[:type] == :set
    assert :ets.info(:monitorex_outbound_recent)[:type] == :ordered_set
    assert :ets.info(:monitorex_outbound_duration_samples)[:type] == :bag
    assert :ets.info(:monitorex_inbound_routes)[:type] == :set
    assert :ets.info(:monitorex_inbound_consumers)[:type] == :set
    assert :ets.info(:monitorex_inbound_recent)[:type] == :ordered_set
    assert :ets.info(:monitorex_inbound_duration_samples)[:type] == :bag
    assert :ets.info(:monitorex_slow_outbound)[:type] == :ordered_set
    assert :ets.info(:monitorex_slow_inbound)[:type] == :ordered_set
  end

  test "reset_ets_tables/1 accepts custom table list" do
    LiveComponentFixtures.reset_ets_tables([:monitorex_outbound_hosts])

    info = :ets.info(:monitorex_outbound_hosts)
    assert info[:name] == :monitorex_outbound_hosts
    assert info[:named_table] == true
    assert info[:type] == :set
  end

  test "reset_ets_tables/1 defaults unknown tables to :set" do
    LiveComponentFixtures.reset_ets_tables([:custom_table])

    info = :ets.info(:custom_table)
    assert info[:name] == :custom_table
    assert info[:named_table] == true
    assert info[:type] == :set
  after
    try do
      :ets.delete(:custom_table)
    rescue
      _ -> :ok
    end
  end
end
