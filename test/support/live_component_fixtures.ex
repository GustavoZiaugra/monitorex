defmodule Monitorex.LiveComponentFixtures do
  @moduledoc """
  Test helpers for LiveComponent tests that need ETS-backed storage.

  Provides functions to reset Monitorex ETS tables and insert sample
  inbound/outbound events without duplicating setup boilerplate across tests.
  """

  alias Monitorex.Event
  alias Monitorex.Storage.ETS

  @tables [
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
  ]

  @type_map %{
    monitorex_outbound_recent: :ordered_set,
    monitorex_inbound_recent: :ordered_set,
    monitorex_outbound_duration_samples: :bag,
    monitorex_inbound_duration_samples: :bag,
    monitorex_slow_outbound: :ordered_set,
    monitorex_slow_inbound: :ordered_set
  }

  @doc """
  Deletes and recreates all Monitorex ETS storage tables.
  """
  @spec reset_ets_tables() :: :ok
  def reset_ets_tables do
    reset_ets_tables(@tables)
  end

  @doc """
  Deletes and recreates the given list of ETS tables.
  Table types are auto-detected based on known names; unrecognised names default to `:set`.
  """
  @spec reset_ets_tables([atom()]) :: :ok
  def reset_ets_tables(tables) do
    Enum.each(tables, fn table ->
      try do
        :ets.delete(table)
      rescue
        _ -> :ok
      end
    end)

    Enum.each(tables, fn table ->
      type = Map.get(@type_map, table, :set)

      :ets.new(table, [:public, :named_table, type, read_concurrency: true])
    end)

    :ok
  end

  @doc """
  Inserts an outbound event into ETS storage.
  """
  @spec insert_outbound_event(keyword()) :: :ok
  def insert_outbound_event(attrs \\ []) do
    attrs =
      Keyword.merge(
        [
          source: :tesla,
          direction: :outbound,
          method: "GET",
          host: "api.example.com",
          path: "/users",
          full_url: "https://api.example.com/users",
          status: 200,
          status_class: :success,
          duration_ms: 12.5,
          timestamp: System.system_time(:microsecond)
        ],
        attrs
      )

    ETS.record_event(struct(Event, attrs))
  end

  @doc """
  Inserts an inbound event into ETS storage.
  """
  @spec insert_inbound_event(keyword()) :: :ok
  def insert_inbound_event(attrs \\ []) do
    attrs =
      Keyword.merge(
        [
          source: :phoenix,
          direction: :inbound,
          method: "GET",
          host: "app.local",
          path: "/api/items",
          full_url: "http://app.local/api/items",
          status: 200,
          status_class: :success,
          duration_ms: 15.0,
          consumer: "svc-a",
          timestamp: System.system_time(:microsecond)
        ],
        attrs
      )

    ETS.record_event(struct(Event, attrs))
  end
end
