defmodule Monitorex do
  @moduledoc """
  Monitorex provides HTTP monitoring capabilities.

  This is the main entry point for the library. Start monitoring by
  configuring sources and mounting the dashboard in your Phoenix router.

  ## Configuration

      config :monitorex, :sources, [:tesla, :finch, :req, :phoenix]

  See the [Getting Started guide](guides/getting_started.md) for setup instructions.
  """

  @ets_tables ~w(monitorex_outbound_hosts monitorex_outbound_endpoints
                 monitorex_outbound_recent monitorex_outbound_duration_samples
                 monitorex_inbound_routes monitorex_inbound_consumers
                 monitorex_inbound_recent monitorex_inbound_duration_samples
                 monitorex_dedup)a

  @doc """
  Returns per-table and total ETS memory usage in words.

  Use this to monitor Monitorex's memory footprint at runtime.

  Returns a map with `:tables` (per-table details), `:total_words`,
  and `:total_kb`.
  """
  def memory_usage do
    tables =
      Map.new(@ets_tables, fn table ->
        size =
          case :ets.info(table, :size) do
            n when is_integer(n) -> n
            _ -> 0
          end

        memory =
          case :ets.info(table, :memory) do
            n when is_integer(n) -> n
            _ -> 0
          end

        {table, %{size: size, memory_words: memory}}
      end)

    total_words =
      Enum.reduce(tables, 0, fn {_name, %{memory_words: m}}, acc -> acc + m end)

    %{
      tables: tables,
      total_words: total_words,
      total_kb: round(total_words * :erlang.system_info(:wordsize) / 1024 * 100) / 100
    }
  end
end
