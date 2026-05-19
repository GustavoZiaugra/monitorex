defmodule Monitorex.ApiPlug do
  @moduledoc """
  REST API plug for programmatic access to Monitorex telemetry data.

  Mount inside your router:

      scope "/monitorex/api" do
        forward "/", Monitorex.ApiPlug, []
      end

  ## Endpoints

  See `Monitorex.Api` or the README for endpoint documentation.
  """

  import Plug.Conn
  alias Monitorex.{Api, Storage}

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    conn = Api.set_cors(conn)

    # Handle CORS preflight
    if conn.method == "OPTIONS" do
      conn
      |> send_resp(204, "")
    else
      handle_request(conn, conn.method, conn.path_info)
    end
  end

  # ── Route Dispatch ──

  defp handle_request(conn, "GET", path) do
    path_parts = path |> Enum.reject(&(&1 == ""))
    dispatch(conn, path_parts)
  end

  defp handle_request(conn, _method, _path) do
    Api.json_error(conn, "Method not allowed. Only GET and OPTIONS are supported.", 405)
  end

  defp dispatch(conn, ["hosts"]) do
    data = Storage.list_hosts()
    Api.json_ok(conn, data)
  end

  defp dispatch(conn, ["hosts" | rest]) do
    host = Enum.join(rest, "/")

    endpoints = Storage.list_endpoints_for_host(host)

    if endpoints == [] do
      Api.json_error(conn, "Host not found", 404)
    else
      # Get the host aggregate
      hosts = Storage.list_hosts()
      host_entry = Enum.find(hosts, %{}, &(&1.host == host))

      data = %{
        host: host,
        requests: host_entry[:requests] || 0,
        errors: host_entry[:errors] || 0,
        error_rate: Api.error_rate(host_entry[:error_rate]),
        avg_latency: host_entry[:avg_latency] || 0.0,
        p50: host_entry[:p50] || 0.0,
        p95: host_entry[:p95] || 0.0,
        p99: host_entry[:p99] || 0.0,
        last_seen: host_entry[:last_seen],
        endpoints: endpoints
      }

      Api.json_ok(conn, data)
    end
  end

  defp dispatch(conn, ["routes"]) do
    data = Storage.list_routes()
    Api.json_ok(conn, data)
  end

  defp dispatch(conn, ["consumers"]) do
    data = Storage.list_consumers()
    Api.json_ok(conn, data)
  end

  defp dispatch(conn, ["events"]) do
    params = conn.params
    filters = Api.parse_filters(params)
    direction = Map.get(params, "direction", "outbound")
    method = Map.get(params, "method")
    since_us = Keyword.get(filters, :since)
    status_code = Keyword.get(filters, :status)

    {events, total_count} =
      case direction do
        "inbound" ->
          raw = Storage.list_recent_inbound(filters)
          total = Storage.count_recent_inbound(filters)
          {raw, total}

        _ ->
          raw = Storage.list_recent_outbound(filters)
          total = Storage.count_recent_outbound(filters)
          {raw, total}
      end

    # Apply post-filters for method, status code, and since
    filtered =
      events
      |> Enum.filter(fn e -> filter_method(e, method) end)
      |> Enum.filter(fn e -> filter_status(e, status_code) end)
      |> Enum.filter(fn e -> filter_since(e, since_us) end)

    returned_count = length(filtered)

    total_count =
      if method || status_code || since_us do
        # With post-filters, total count is what was returned
        returned_count
      else
        total_count
      end

    api_data = Enum.map(filtered, &Api.event_to_api/1)
    headers = Api.pagination_headers(total_count, filters, returned_count)

    Api.json_ok(conn, api_data, headers: headers)
  end

  defp dispatch(conn, ["events" | id_parts]) do
    id_str = Enum.join(id_parts, "/")

    case Integer.parse(id_str) do
      {timestamp, _} ->
        case Storage.get_event(timestamp) do
          nil -> Api.json_error(conn, "Event not found", 404)
          event -> Api.json_ok(conn, Api.event_to_api(event))
        end

      :error ->
        Api.json_error(conn, "Invalid event ID. Must be a numeric timestamp.", 400)
    end
  end

  defp dispatch(conn, ["metrics"]) do
    params = conn.params
    _filters = Api.parse_filters(params)
    host = Map.get(params, "host")
    window_secs = params |> Map.get("window", "300") |> parse_int(300)

    # Get host-level metrics
    hosts = Storage.list_hosts()
    host_data =
      if host do
        Enum.find(hosts, %{}, &(&1.host == host))
      else
        # Aggregate across all hosts
        %{
          requests: Enum.reduce(hosts, 0, fn h, acc -> acc + (h.requests || 0) end),
          errors: Enum.reduce(hosts, 0, fn h, acc -> acc + (h.errors || 0) end),
          avg_latency: compute_aggregate_avg(hosts, :avg_latency, &(&1.requests || 0)),
          p50: compute_aggregate_p(hosts, :p50),
          p95: compute_aggregate_p(hosts, :p95),
          p99: compute_aggregate_p(hosts, :p99)
        }
      end

    # Compute RPS from recent events within the window
    now_us = System.system_time(:microsecond)
    window_us = window_secs * 1_000_000
    cutoff = now_us - window_us

    recent_outbound = Storage.list_recent_outbound(limit: 500)

    windowed =
      Enum.filter(recent_outbound, fn %{timestamp: ts} ->
        is_integer(ts) and ts >= cutoff
      end)

    rps =
      if window_secs > 0 and windowed != [] do
        # Approximate: requests_in_window / window_secs
        Float.round(length(windowed) / window_secs, 2)
      else
        0.0
      end

    # Error rate in window
    window_errors = Enum.count(windowed, fn e -> is_integer(e.status) and e.status >= 400 end)
    window_error_rate =
      if windowed != [] do
        Float.round(window_errors / length(windowed) * 100, 2)
      else
        0.0
      end

    data = %{
      hosts_count: length(hosts),
      total_requests: host_data[:requests] || 0,
      total_errors: host_data[:errors] || 0,
      error_rate: Api.error_rate(host_data[:error_rate]),
      avg_latency: host_data[:avg_latency] || 0.0,
      p50: host_data[:p50] || 0.0,
      p95: host_data[:p95] || 0.0,
      p99: host_data[:p99] || 0.0,
      window_seconds: window_secs,
      rps: rps,
      window_error_rate: window_error_rate,
      window_errors: window_errors,
      window_requests: length(windowed)
    }

    Api.json_ok(conn, data)
  end

  defp dispatch(conn, ["health"]) do
    health = Monitorex.Health.check()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(health))
  end

  defp dispatch(conn, _) do
    Api.json_error(conn, "Not found. See /monitorex/api for available endpoints.", 404)
  end

  # ── Filter helpers ──

  defp filter_method(_event, nil), do: true
  defp filter_method(%{method: m}, filter) when is_binary(m) do
    String.upcase(m) == String.upcase(filter)
  end
  defp filter_method(_, _), do: false

  defp filter_status(_event, nil), do: true
  defp filter_status(%{status: s}, code) when is_integer(s), do: s == code
  defp filter_status(_, _), do: false

  defp filter_since(_event, nil), do: true
  defp filter_since(%{timestamp: ts}, cutoff) when is_integer(ts), do: ts >= cutoff
  defp filter_since(_, _), do: false

  # ── Private helpers ──

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default
  defp parse_int(str, _default) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end
  defp parse_int(n, _default) when is_integer(n), do: n
  defp parse_int(_, default), do: default

  defp compute_aggregate_avg(items, key, weight_fn) do
    total_weight = Enum.sum(items |> Enum.map(weight_fn))

    if total_weight > 0 do
      sum = Enum.reduce(items, 0.0, fn item, acc ->
        acc + (Map.get(item, key) || 0.0) * weight_fn.(item)
      end)
      sum / total_weight
    else
      0.0
    end
  end

  defp compute_aggregate_p(hosts, key) do
    values =
      hosts
      |> Enum.map(&Map.get(&1, key))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&is_number/1)

    if values == [] do
      0.0
    else
      Enum.sum(values) / length(values)
    end
  end
end
