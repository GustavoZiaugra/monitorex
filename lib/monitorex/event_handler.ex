defmodule Monitorex.EventHandler do
  @moduledoc """
  Handles telemetry events from Tesla, Finch, Req, and Phoenix, transforming them
  into `Monitorex.Event` structs.

  Each handler function follows the `Telemetry` handler callback signature:
  `(event_name, measurements, metadata, config)`.
  """

  alias Monitorex.Event
  alias Monitorex.UrlNormalizer
  alias Monitorex.URLRedactor
  alias Monitorex.ConsumerIdentifier
  alias Monitorex.HeaderRedactor

  @doc """
  Handles a Tesla telemetry event (`[:tesla, :request, :stop]`).

  Parses the metadata and measurements into a `Monitorex.Event` struct with
  source `:tesla` and direction `:outbound`.

  The URL is normalised via `UrlNormalizer.normalize/1` and sensitive query
  parameters are redacted via `URLRedactor.redact/1`.

  ## Telemetry metadata shape

      %{
        url:  %URI{},
        method: :get | :post | …,
        status: 200,
        pid: pid,
        monotonic_time: integer
      }

  The `dedup_key` is set to `{pid, monotonic_time}` for deduplication.
  """
  @spec handle_tesla_event(
          event_name :: [atom()],
          measurements :: map(),
          metadata :: map(),
          config :: keyword()
        ) :: Event.t() | nil
  def handle_tesla_event([:tesla, :request, :stop], measurements, metadata, _config) do
    # Support both legacy Tesla telemetry (flat keys) and modern Tesla (env struct)
    {url_str, method, status, req_headers, resp_headers, ts, pid} =
      case metadata do
        %{env: %{url: url, method: m, status: s} = env} ->
          url_str = url_to_string(url)

          {url_str, Event.normalize_method(m), s, redact_headers_from_metadata(env.headers || []),
           redact_headers_from_metadata(env.headers || []),
           metadata[:monotonic_time] || measurements[:monotonic_time] || System.monotonic_time(),
           metadata[:pid] || self()}

        %{url: url, method: m, status: s} ->
          url_str = url_to_string(url)

          {url_str, Event.normalize_method(m), s,
           redact_headers_from_metadata(metadata[:req_headers]),
           redact_headers_from_metadata(metadata[:resp_headers]),
           metadata[:monotonic_time] || measurements[:monotonic_time] || System.monotonic_time(),
           metadata[:pid] || self()}
      end

    normalized_url = UrlNormalizer.normalize(url_str)
    redacted_url = URLRedactor.redact(normalized_url)
    %URI{host: host, path: path} = URI.parse(normalized_url)

    %Event{
      source: :tesla,
      direction: :outbound,
      method: method,
      host: host,
      path: path,
      full_url: redacted_url,
      status: status,
      status_class: Event.classify_status(status || 0),
      duration_ms: Event.duration_ms(measurements.duration),
      timestamp: ts,
      dedup_key: {pid, ts},
      request_headers: req_headers,
      response_headers: resp_headers,
      request_body: maybe_store_body(metadata[:request_body], :request),
      response_body: maybe_store_body(metadata[:response_body], :response)
    }
  end

  def handle_tesla_event([:tesla, :request, :exception], measurements, metadata, _config) do
    {url_str, method, req_headers, ts, pid} =
      case metadata do
        %{env: %{url: url, method: m} = env} ->
          {url_to_string(url), Event.normalize_method(m),
           redact_headers_from_metadata(env.headers || []),
           metadata[:monotonic_time] || measurements[:monotonic_time] || System.monotonic_time(),
           metadata[:pid] || self()}

        %{url: url, method: m} ->
          {url_to_string(url), Event.normalize_method(m),
           redact_headers_from_metadata(metadata[:req_headers]),
           metadata[:monotonic_time] || measurements[:monotonic_time] || System.monotonic_time(),
           metadata[:pid] || self()}

        _ ->
          {"unknown", "UNKNOWN", [], System.monotonic_time(), self()}
      end

    normalized_url = if url_str != "unknown", do: UrlNormalizer.normalize(url_str), else: url_str
    redacted_url = URLRedactor.redact(normalized_url)

    %Event{
      source: :tesla,
      direction: :outbound,
      method: method,
      host: URI.parse(normalized_url).host,
      path: URI.parse(normalized_url).path,
      full_url: redacted_url,
      status: nil,
      status_class: :server_error,
      duration_ms: Event.duration_ms(measurements.duration),
      timestamp: ts,
      dedup_key: {pid, ts},
      error: inspect(metadata[:reason] || metadata[:kind] || "Tesla exception"),
      request_headers: req_headers,
      response_headers: nil
    }
  end

  # Catch-all for unexpected Tesla telemetry events
  def handle_tesla_event(_event_name, _measurements, _metadata, _config), do: nil

  @doc """
  Handles a Finch telemetry event (`[:finch, :request, :stop]`).

  Parses the metadata and measurements into a `Monitorex.Event` struct with
  source `:finch` and direction `:outbound`.

  ## Telemetry metadata shape

      %{
        url:  %URI{} | String.t(),
        method: :get | "GET" | …,
        status: 200,
        pid: pid,
        monotonic_time: integer
      }

  The `url` field may be a `URI.t()` struct or a string; both are handled.
  The `method` field may be an atom or string; both are normalised.
  """
  @spec handle_finch_event(
          event_name :: [atom()],
          measurements :: map(),
          metadata :: map(),
          config :: keyword()
        ) :: Event.t() | nil
  def handle_finch_event([:finch, :request, :stop], measurements, metadata, _config) do
    {url_str, method, host, path, req_headers, status} =
      case metadata do
        %{request: %{method: m} = req} ->
          # New Finch telemetry format (Finch.Request struct)
          url = build_finch_url(req)

          {url, Event.normalize_method(m), req.host, URI.parse(url).path,
           redact_headers_from_metadata(req.headers || []), extract_finch_status(metadata)}

        %{url: url, method: m, status: s} ->
          # Legacy Finch telemetry format
          url_str = url_to_string(url)
          uri = URI.parse(url_str)

          {url_str, Event.normalize_method(m), Event.extract_host(url), uri.path,
           redact_headers_from_metadata(metadata[:req_headers] || []), s}
      end

    resp_headers = redact_headers_from_metadata(metadata[:resp_headers] || [])

    ts = metadata[:monotonic_time] || measurements[:monotonic_time] || System.monotonic_time()
    pid = metadata[:pid] || self()

    %Event{
      source: :finch,
      direction: :outbound,
      method: method,
      host: host,
      path: path,
      full_url: URLRedactor.redact(url_str),
      status: status,
      status_class: Event.classify_status(status || 0),
      duration_ms: Event.duration_ms(measurements.duration),
      timestamp: ts,
      dedup_key: {pid, ts},
      request_headers: req_headers,
      response_headers: resp_headers,
      request_body: maybe_store_body(metadata[:request_body], :request),
      response_body: maybe_store_body(metadata[:response_body], :response)
    }
  end

  def handle_finch_event([:finch, :request, :exception], measurements, metadata, _config) do
    ts = metadata[:monotonic_time] || measurements[:monotonic_time] || System.monotonic_time()
    pid = metadata[:pid] || self()

    case metadata do
      %{request: request} ->
        url_str = build_finch_url(request)

        %Event{
          source: :finch,
          direction: :outbound,
          method: Event.normalize_method(request.method),
          host: request.host,
          path: URI.parse(url_str).path,
          full_url: URLRedactor.redact(url_str),
          status: nil,
          status_class: :server_error,
          duration_ms: Event.duration_ms(measurements.duration),
          timestamp: ts,
          dedup_key: {pid, ts},
          error: inspect(metadata[:reason] || metadata[:result] || "Finch exception"),
          request_headers: redact_headers_from_metadata(request.headers || []),
          response_headers: nil
        }

      _ ->
        %Event{
          source: :finch,
          direction: :outbound,
          method: nil,
          host: nil,
          path: nil,
          full_url: "unknown",
          status: nil,
          status_class: :server_error,
          duration_ms: Event.duration_ms(measurements.duration),
          timestamp: ts,
          dedup_key: {pid, ts},
          error: "Finch exception",
          request_headers: [],
          response_headers: nil
        }
    end
  end

  # Catch-all for unexpected Finch telemetry events
  def handle_finch_event(_event_name, _measurements, _metadata, _config), do: nil

  defp build_finch_url(%{scheme: scheme, host: host, port: port, path: path} = req) do
    query = if req.query && req.query != "", do: "?#{req.query}", else: ""
    "#{scheme}://#{host}#{if port != 443 && port != 80, do: ":#{port}"}#{path}#{query}"
  end

  defp build_finch_url(_), do: nil

  defp extract_finch_status(metadata) do
    case metadata[:response] do
      %{status: status} ->
        status

      _ ->
        case metadata[:result] do
          {:ok, %{status: status}} -> status
          _ -> metadata[:status]
        end
    end
  end

  @doc """
  Handles a Req telemetry event (`[:req, :stop]`).

  Parses the metadata and measurements into a `Monitorex.Event` struct with
  source `:req` and direction `:outbound`.

  ## Telemetry metadata shape

      %{
        request:  %Req.Request{},
        response: %Req.Response{}
      }

  The `Req.Request` struct contains `:url` (a URI.t()), `:method`, and `:headers`.
  The `Req.Response` struct contains `:status`, `:headers`, and `:body`.
  Duration is in `measurements.duration` (native time units).
  """
  @spec handle_req_event(
          event_name :: [atom()],
          measurements :: map(),
          metadata :: map(),
          config :: keyword()
        ) :: Event.t() | nil
  def handle_req_event([:req, :stop], measurements, metadata, _config) do
    request = metadata.request
    response = metadata.response

    url_str = url_to_string(request.url)
    method = Event.normalize_method(request.method)
    uri = URI.parse(url_str)
    host = uri.host
    path = uri.path

    req_headers = redact_headers_from_metadata(request.headers || [])
    resp_headers = redact_headers_from_metadata(response.headers || [])

    ts = metadata[:monotonic_time] || measurements[:monotonic_time] || System.monotonic_time()

    normalized_url = UrlNormalizer.normalize(url_str)
    redacted_url = URLRedactor.redact(normalized_url)

    %Event{
      source: :req,
      direction: :outbound,
      method: method,
      host: host,
      path: path,
      full_url: redacted_url,
      status: response.status,
      status_class: Event.classify_status(response.status || 0),
      duration_ms: Event.duration_ms(measurements.duration),
      timestamp: ts,
      request_headers: req_headers,
      response_headers: resp_headers
    }
  end

  def handle_req_event([:req, :exception], measurements, metadata, _config) do
    request = metadata.request

    url_str = url_to_string(request.url)
    method = Event.normalize_method(request.method)
    uri = URI.parse(url_str)

    ts = metadata[:monotonic_time] || measurements[:monotonic_time] || System.monotonic_time()

    %Event{
      source: :req,
      direction: :outbound,
      method: method,
      host: uri.host,
      path: uri.path,
      full_url: URLRedactor.redact(url_str),
      status: nil,
      status_class: :server_error,
      duration_ms: Event.duration_ms(measurements.duration),
      timestamp: ts,
      request_headers: redact_headers_from_metadata(request.headers || []),
      response_headers: nil,
      error: inspect(metadata[:error] || "Req exception")
    }
  end

  # Catch-all for unexpected Req telemetry events
  def handle_req_event(_event_name, _measurements, _metadata, _config), do: nil

  @doc """
  Handles a Phoenix telemetry event (`[:phoenix, :router_dispatch, :stop]`).

  Parses the metadata and measurements into a `Monitorex.Event` struct with
  source `:phoenix` and direction `:inbound`.

  The consumer is extracted via `ConsumerIdentifier.identify/1`.

  If the application config key `:inbound_path_prefixes` is set to a list of
  path prefixes, only requests whose path starts with one of the prefixes
  produce an event.  Returns `nil` (i.e. the event is filtered) when no
  prefix matches.

  ## Telemetry metadata shape

      %{
        conn: %Plug.Conn{}
      }

  """
  @spec handle_phoenix_event(
          event_name :: [atom()],
          measurements :: map(),
          metadata :: map(),
          config :: keyword()
        ) :: Event.t() | nil
  def handle_phoenix_event([:phoenix, :router_dispatch, :stop], measurements, metadata, _config) do
    conn = metadata.conn
    path = conn.request_path

    inbound_path_prefixes = Application.get_env(:monitorex, :inbound_path_prefixes, nil)

    if accepts_path?(path, inbound_path_prefixes) do
      req_headers = redact_headers_from_metadata(conn.req_headers)
      resp_headers = redact_headers_from_metadata(conn.resp_headers)

      %Event{
        source: :phoenix,
        direction: :inbound,
        method: conn.method,
        host: conn.host,
        path: path,
        full_url: conn.request_path,
        status: conn.status,
        status_class: Event.classify_status(conn.status),
        duration_ms: Event.duration_ms(measurements.duration),
        consumer: ConsumerIdentifier.identify(conn),
        timestamp: System.monotonic_time(),
        dedup_key: {self(), System.monotonic_time()},
        request_headers: req_headers,
        response_headers: resp_headers,
        request_body: maybe_store_body(metadata[:request_body], :request),
        response_body: maybe_store_body(metadata[:response_body], :response)
      }
    end
  end

  # Catch-all for unexpected Phoenix telemetry events
  def handle_phoenix_event(_event_name, _measurements, _metadata, _config), do: nil

  # ── private helpers ──

  defp redact_headers_from_metadata(nil), do: nil
  defp redact_headers_from_metadata([]), do: []

  defp redact_headers_from_metadata(headers) when is_list(headers) do
    HeaderRedactor.redact_headers(headers)
  end

  defp maybe_store_body(body, _direction) when is_nil(body) or not is_binary(body), do: nil

  defp maybe_store_body(body, :request) do
    if Application.get_env(:monitorex, :store_request_body, false), do: body, else: nil
  end

  defp maybe_store_body(body, :response) do
    if Application.get_env(:monitorex, :store_response_body, false), do: body, else: nil
  end

  # Converts a URI struct or string URL to a string
  defp url_to_string(%URI{} = uri), do: URI.to_string(uri)
  defp url_to_string(url) when is_binary(url), do: url

  defp accepts_path?(_path, nil), do: true

  defp accepts_path?(path, prefixes) when is_list(prefixes) do
    Enum.any?(prefixes, &String.starts_with?(path, &1))
  end
end
