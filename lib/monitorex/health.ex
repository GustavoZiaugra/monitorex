defmodule Monitorex.Health do
  @moduledoc """
  Health check module for Monitorex.

  Gathers Collector status, ETS table sizes, event throughput, and
  overall health of the monitoring pipeline.  Designed for load balancer
  probes, Kubernetes liveness checks, and operational dashboards.

  ## Usage

      iex> Monitorex.Health.check()
      %{status: :healthy, uptime: ..., ets_table_sizes: %{}, ...}
  """

  @tables ~w(monitorex_outbound_hosts monitorex_outbound_endpoints
             monitorex_outbound_recent monitorex_outbound_duration_samples
             monitorex_inbound_routes monitorex_inbound_consumers
             monitorex_inbound_recent monitorex_inbound_duration_samples)a

  @doc """
  Returns a map of Collector health statistics.

  The `:status` field is one of `:healthy`, `:degraded`, or `:unhealthy`.
  """
  def check do
    collector_alive = Process.whereis(Monitorex.Collector) != nil

    {msg_queue, uptime} =
      if collector_alive do
        pid = Process.whereis(Monitorex.Collector)
        info = Process.info(pid, [:message_queue_len, :dictionary])
        msg_q = Keyword.get(info || [], :message_queue_len, 0)
        _dict = Keyword.get(info || [], :dictionary, [])
        # Find start time from collector state or use 0
        start_time =
          try do
            state = :sys.get_state(pid)
            Map.get(state, :start_time, 0)
          rescue
            _ -> 0
          end
        elapsed = if start_time > 0, do: div(System.monotonic_time() - start_time, 1_000_000_000), else: 0
        {msg_q, elapsed}
      else
        {0, 0}
      end

    ets_sizes = ets_table_sizes()
    status = compute_status(collector_alive, msg_queue, ets_sizes)

    %{
      status: status,
      collector_alive: collector_alive,
      message_queue_len: msg_queue,
      uptime_seconds: uptime,
      ets_table_sizes: ets_sizes,
      total_ets_memory_words: total_ets_memory(ets_sizes),
      checked_at: System.system_time(:second)
    }
  end

  @doc false
  def ets_table_sizes do
    Map.new(@tables, fn table ->
      size = case :ets.info(table, :size) do; n when is_integer(n) -> n; _ -> 0; end
      {table, size}
    end)
  end

  defp compute_status(true, msg_queue, _ets) when msg_queue > 10_000, do: :unhealthy
  defp compute_status(true, msg_queue, _ets) when msg_queue > 1_000, do: :degraded

  defp compute_status(true, _msg_queue, ets) do
    outbound_recent = Map.get(ets, :monitorex_outbound_recent, 0)
    inbound_recent = Map.get(ets, :monitorex_inbound_recent, 0)
    max_recent = Application.get_env(:monitorex, :max_recent, 500)

    if outbound_recent > max_recent * 0.9 or inbound_recent > max_recent * 0.9 do
      :degraded
    else
      :healthy
    end
  end

  defp compute_status(false, _msg_queue, _ets), do: :unhealthy

  defp total_ets_memory(_ets) do
    Enum.reduce(@tables, 0, fn table, acc ->
      case :ets.info(table, :memory) do
        n when is_integer(n) -> acc + n
        _ -> acc
      end
    end)
  end
end
