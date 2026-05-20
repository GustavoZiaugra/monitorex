defmodule Monitorex.Api do
  @moduledoc """
  Response helpers and shared utilities for the Monitorex REST API.

  Provides consistent JSON envelopes, CORS headers, pagination, and
  filter parsing used by `Monitorex.ApiPlug`.
  """

  import Plug.Conn

  @doc """
  Sends a success response with the given data.

  Envelope: `{"ok": true, "data": ...}`
  """
  @spec json_ok(Plug.Conn.t(), term(), keyword()) :: Plug.Conn.t()
  def json_ok(conn, data, opts \\ []) do
    headers = Keyword.get(opts, :headers, [])
    status = Keyword.get(opts, :status, 200)

    conn
    |> merge_resp_headers(headers)
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{ok: true, data: data}))
  end

  @doc """
  Sends an error response.

  Envelope: `{"ok": false, "error": message}`
  """
  @spec json_error(Plug.Conn.t(), String.t(), integer()) :: Plug.Conn.t()
  def json_error(conn, message, status \\ 400) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{ok: false, error: message}))
  end

  @doc """
  Sets CORS headers for cross-origin access.
  """
  @spec set_cors(Plug.Conn.t()) :: Plug.Conn.t()
  def set_cors(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "Content-Type, Authorization")
    |> put_resp_header("access-control-max-age", "86400")
  end

  @doc """
  Parses common query parameters into storage options.

  Supports:
    * `limit` — max results (default: 50, max: 500)
    * `offset` — pagination offset (default: 0)
    * `status` — numeric HTTP status code filter
    * `status_class` — status class atom (:success, :error, :client_error, :server_error, :redirect)
    * `host` — host filter (for outbound events)
    * `method` — HTTP method filter
    * `consumer` — consumer filter (for inbound events)
    * `route` — route key filter (for inbound events)
    * `direction` — "outbound" or "inbound"
    * `since` — ISO 8601 timestamp (filters events after this time, in epoch microseconds)
  """
  @spec parse_filters(map()) :: keyword()
  def parse_filters(params) do
    limit = params |> Map.get("limit", "50") |> parse_int(50) |> min(500) |> max(1)
    offset = params |> Map.get("offset", "0") |> parse_int(0) |> max(0)

    opts = [limit: limit, offset: offset]

    opts = maybe_add(opts, params, "host", :host)
    opts = maybe_add(opts, params, "consumer", :consumer)
    opts = maybe_add(opts, params, "route", :route)
    opts = maybe_add(opts, params, "status_class", :status_class, &String.to_atom/1)
    opts = maybe_add(opts, params, "method", :method)

    opts = maybe_add_status(opts, params)
    opts = maybe_add_since(opts, params)

    opts
  end

  @doc """
  Builds pagination headers for a result set.
  Returns a list of header tuples.
  """
  @spec pagination_headers(integer(), keyword(), integer()) :: [{binary(), binary()}, ...]
  def pagination_headers(total_count, filters, returned_count) do
    limit = Keyword.get(filters, :limit, 50)
    offset = Keyword.get(filters, :offset, 0)

    [
      {"x-total-count", Integer.to_string(total_count)},
      {"x-page-size", Integer.to_string(limit)},
      {"x-page-offset", Integer.to_string(offset)},
      {"x-returned-count", Integer.to_string(returned_count)}
    ]
  end

  @doc """
  Converts an Event struct to a safe API map, removing internal fields.
  """
  @spec event_to_api(Monitorex.Event.t()) :: map()
  def event_to_api(event) do
    %{
      source: event.source,
      direction: event.direction,
      method: event.method,
      host: event.host,
      path: event.path,
      full_url: event.full_url,
      status: event.status,
      status_class: event.status_class,
      duration_ms: event.duration_ms,
      consumer: event.consumer,
      error: event.error,
      timestamp: event.timestamp
    }
  end

  @doc """
  Converts a percentage to a float or returns nil.
  """
  @spec error_rate(term()) :: float() | nil
  def error_rate(nil), do: nil
  def error_rate(rate) when is_number(rate), do: rate
  def error_rate(_), do: nil

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

  defp maybe_add(opts, params, key, opt_key, transform \\ nil) do
    case Map.get(params, key) do
      nil ->
        opts

      "" ->
        opts

      value ->
        transformed = if transform, do: transform.(value), else: value
        Keyword.put(opts, opt_key, transformed)
    end
  end

  defp maybe_add_status(opts, params) do
    case Map.get(params, "status") do
      nil ->
        opts

      "" ->
        opts

      str ->
        case Integer.parse(str) do
          {code, _} -> Keyword.put(opts, :status, code)
          :error -> opts
        end
    end
  end

  defp maybe_add_since(opts, params) do
    case Map.get(params, "since") do
      nil ->
        opts

      "" ->
        opts

      iso_str ->
        case DateTime.from_iso8601(iso_str) do
          {:ok, dt, _} ->
            epoch_us = DateTime.to_unix(dt, :microsecond)
            Keyword.put(opts, :since, epoch_us)

          {:error, _} ->
            opts
        end
    end
  end
end
