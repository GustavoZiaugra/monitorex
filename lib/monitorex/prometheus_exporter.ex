defmodule Monitorex.PrometheusExporter do
  @moduledoc """
  Exports Monitorex metrics in Prometheus text format (plain text, no deps).

  Reads directly from ETS tables — no locks, no side effects.
  Designed for scraping by Prometheus or the Datadog agent.

  ## Usage

      iex> Monitorex.PrometheusExporter.format()
      "# HELP monitorex_requests_total ..."

  The output is a string in Prometheus exposition format:
  https://prometheus.io/docs/instrumenting/exposition_formats/
  """

  @tables ~w(monitorex_outbound_hosts monitorex_outbound_endpoints
             monitorex_outbound_recent monitorex_outbound_duration_samples
             monitorex_inbound_routes monitorex_inbound_consumers
             monitorex_inbound_recent monitorex_inbound_duration_samples)a

  @doc """
  Returns the full Prometheus metrics text.
  """
  def format do
    [
      header(),
      "# TYPE monitorex_requests_total gauge",
      host_request_metrics(),
      endpoint_request_metrics(),
      route_request_metrics(),
      consumer_request_metrics(),
      "",
      "# HELP monitorex_errors_total Total errors by host",
      "# TYPE monitorex_errors_total gauge",
      host_error_metrics(),
      "",
      "# HELP monitorex_latency_seconds Request latency in seconds",
      "# TYPE monitorex_latency_seconds gauge",
      host_latency_metrics(),
      "",
      "# HELP monitorex_events_recent Number of events in ring buffer",
      "# TYPE monitorex_events_recent gauge",
      ring_buffer_metrics(),
      "",
      "# HELP monitorex_ets_size ETS table size in entries",
      "# TYPE monitorex_ets_size gauge",
      ets_size_metrics(),
      ""
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp header do
    "# HELP monitorex_collector_info Monitorex collector metadata\n" <>
      "# TYPE monitorex_collector_info gauge\n" <>
      "monitorex_collector_info{version=\"#{Application.spec(:monitorex, :vsn) || "unknown"}\"} 1"
  end

  # ── Host metrics ──

  defp host_request_metrics do
    with_table(:monitorex_outbound_hosts, fn ->
      :ets.foldl(
        fn {host, agg}, acc ->
          acc <>
            "monitorex_requests_total{host=\"#{escape(host)}\",direction=\"outbound\"} #{agg.requests || 0}\n"
        end,
        "",
        :monitorex_outbound_hosts
      )
    end) || ""
  end

  defp host_error_metrics do
    with_table(:monitorex_outbound_hosts, fn ->
      :ets.foldl(
        fn {host, agg}, acc ->
          acc <>
            "monitorex_errors_total{host=\"#{escape(host)}\",direction=\"outbound\"} #{agg.errors || 0}\n"
        end,
        "",
        :monitorex_outbound_hosts
      )
    end) || ""
  end

  defp host_latency_metrics do
    with_table(:monitorex_outbound_hosts, fn ->
      :ets.foldl(
        fn {host, agg}, acc ->
          p50 =
            if agg[:p50],
              do:
                "monitorex_latency_seconds{host=\"#{escape(host)}\",quantile=\"p50\"} #{agg.p50 / 1000}\n",
              else: ""

          p95 =
            if agg[:p95],
              do:
                "monitorex_latency_seconds{host=\"#{escape(host)}\",quantile=\"p95\"} #{agg.p95 / 1000}\n",
              else: ""

          p99 =
            if agg[:p99],
              do:
                "monitorex_latency_seconds{host=\"#{escape(host)}\",quantile=\"p99\"} #{agg.p99 / 1000}\n",
              else: ""

          acc <> p50 <> p95 <> p99
        end,
        "",
        :monitorex_outbound_hosts
      )
    end) || ""
  end

  # ── Endpoint metrics ──

  defp endpoint_request_metrics do
    with_table(:monitorex_outbound_endpoints, fn ->
      :ets.foldl(
        fn {{host, path}, agg}, acc ->
          acc <>
            "monitorex_requests_total{host=\"#{escape(host)}\",path=\"#{escape(path)}\",direction=\"outbound\",resource=\"endpoint\"} #{agg.requests || 0}\n"
        end,
        "",
        :monitorex_outbound_endpoints
      )
    end) || ""
  end

  # ── Route metrics ──

  defp route_request_metrics do
    with_table(:monitorex_inbound_routes, fn ->
      :ets.foldl(
        fn {route_key, agg}, acc ->
          [method, path] = String.split(route_key, ":", parts: 2)

          acc <>
            "monitorex_requests_total{method=\"#{escape(method)}\",path=\"#{escape(path)}\",direction=\"inbound\",resource=\"route\"} #{agg.requests || 0}\n"
        end,
        "",
        :monitorex_inbound_routes
      )
    end) || ""
  end

  # ── Consumer metrics ──

  defp consumer_request_metrics do
    with_table(:monitorex_inbound_consumers, fn ->
      :ets.foldl(
        fn {consumer, agg}, acc ->
          acc <>
            "monitorex_requests_total{consumer=\"#{escape(consumer)}\",direction=\"inbound\",resource=\"consumer\"} #{agg.requests || 0}\n"
        end,
        "",
        :monitorex_inbound_consumers
      )
    end) || ""
  end

  # ── Ring buffer metrics ──

  defp ring_buffer_metrics do
    out = ets_size(:monitorex_outbound_recent)
    inn = ets_size(:monitorex_inbound_recent)

    "monitorex_events_recent{direction=\"outbound\"} #{out}\n" <>
      "monitorex_events_recent{direction=\"inbound\"} #{inn}"
  end

  # ── ETS table size metrics ──

  defp ets_size_metrics do
    Enum.map(@tables, fn table ->
      name = table |> Atom.to_string() |> String.replace("monitorex_", "")
      size = ets_size(table)
      "monitorex_ets_size{table=\"#{name}\"} #{size}"
    end)
    |> Enum.join("\n")
  end

  # ── Helpers ──

  defp ets_size(table) do
    case :ets.info(table, :size) do
      n when is_integer(n) -> n
      _ -> 0
    end
  end

  defp with_table(name, fun) do
    case :ets.info(name) do
      :undefined -> nil
      _ -> fun.()
    end
  end

  defp escape(value) when is_binary(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp escape(_), do: ""
end
