defmodule Monitorex.EventHandler do
  @moduledoc """
  Handles telemetry events from Tesla, Finch, and Phoenix, transforming them
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
        ) :: Event.t()
  def handle_tesla_event([:tesla, :request, :stop], measurements, metadata, _config) do
    url_str = metadata.url |> URI.to_string()
    normalized_url = UrlNormalizer.normalize(url_str)
    redacted_url = URLRedactor.redact(normalized_url)
    %URI{host: host, path: path} = URI.parse(normalized_url)

    %Event{
      source: :tesla,
      direction: :outbound,
      method: Event.normalize_method(metadata.method),
      host: host,
      path: path,
      full_url: redacted_url,
      status: metadata.status,
      status_class: Event.classify_status(metadata.status),
      duration_ms: Event.duration_ms(measurements.duration),
      timestamp: metadata.monotonic_time,
      dedup_key: {metadata.pid, metadata.monotonic_time},
      request_headers: redact_headers(metadata[:req_headers]),
      response_headers: redact_headers(metadata[:resp_headers])
    }
  end

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
        ) :: Event.t()
  def handle_finch_event([:finch, :request, :stop], measurements, metadata, _config) do
    url_str = url_to_string(metadata.url)
    host = Event.extract_host(metadata.url)
    uri = URI.parse(url_str)

    %Event{
      source: :finch,
      direction: :outbound,
      method: Event.normalize_method(metadata.method),
      host: host,
      path: uri.path,
      full_url: URLRedactor.redact(url_str),
      status: metadata.status,
      status_class: Event.classify_status(metadata.status),
      duration_ms: Event.duration_ms(measurements.duration),
      timestamp: metadata.monotonic_time,
      dedup_key: {metadata.pid, metadata.monotonic_time},
      request_headers: redact_headers(metadata[:req_headers]),
      response_headers: redact_headers(metadata[:resp_headers])
    }
  end

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
        request_headers: redact_headers(conn.req_headers),
        response_headers: redact_headers(conn.resp_headers)
      }
    end
  end

  # ── private helpers ──

  defp url_to_string(%URI{} = uri), do: URI.to_string(uri)
  defp url_to_string(url) when is_binary(url), do: url

  defp accepts_path?(_path, nil), do: true
  defp accepts_path?(path, prefixes) when is_list(prefixes) do
    Enum.any?(prefixes, &String.starts_with?(path, &1))
  end

  defp redact_headers(nil), do: nil

  defp redact_headers(headers) when is_list(headers) do
    redacted_list = Application.get_env(:monitorex, :redacted_headers, HeaderRedactor.default_redacted_headers())
    HeaderRedactor.redact_headers(headers, redacted_list)
  end
end
