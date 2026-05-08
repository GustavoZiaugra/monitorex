defmodule Monitorex.Event do
  @moduledoc """
  Represents a monitored HTTP event (inbound or outbound).

  Contains all relevant fields for recording and displaying HTTP telemetry data
  collected from Tesla, Finch, and Phoenix telemetry events.
  """

  defstruct [
    :source,
    :direction,
    :method,
    :host,
    :path,
    :full_url,
    :status,
    :status_class,
    :duration_ms,
    :consumer,
    :error,
    :timestamp,
    :dedup_key,
    :request_headers,
    :response_headers,
    :request_body,
    :response_body
  ]

  @type t :: %__MODULE__{
          source: atom(),
          direction: :inbound | :outbound,
          method: String.t(),
          host: String.t() | nil,
          path: String.t() | nil,
          full_url: String.t() | nil,
          status: non_neg_integer() | nil,
          status_class: atom(),
          duration_ms: float(),
          consumer: String.t() | nil,
          error: String.t() | nil,
          timestamp: integer(),
          dedup_key: term(),
          request_headers: keyword() | nil,
          response_headers: keyword() | nil,
          request_body: binary() | nil,
          response_body: binary() | nil
        }

  @doc """
  Classifies an HTTP status code into a status class atom.

  ## Examples

      iex> Monitorex.Event.classify_status(200)
      :success

      iex> Monitorex.Event.classify_status(301)
      :redirect

      iex> Monitorex.Event.classify_status(404)
      :client_error

      iex> Monitorex.Event.classify_status(500)
      :server_error

  """
  @spec classify_status(status :: integer()) :: :success | :redirect | :client_error | :server_error
  def classify_status(status) when status >= 200 and status < 300, do: :success
  def classify_status(status) when status >= 300 and status < 400, do: :redirect
  def classify_status(status) when status >= 400 and status < 500, do: :client_error
  def classify_status(status) when status >= 500, do: :server_error

  @doc """
  Converts a time value from the native time unit to milliseconds as a float.

  ## Examples

      iex> Monitorex.Event.duration_ms(1_000_000)
      1.0

      iex> Monitorex.Event.duration_ms(0)
      0.0

  """
  @spec duration_ms(time :: integer()) :: float()
  def duration_ms(time) when is_integer(time) do
    time / System.convert_time_unit(1, :millisecond, :native)
  end

  @doc """
  Normalizes a method atom (or string) to an uppercase string.

  Tesla and Finch pass method as atoms (`:get`, `:post`); this converts
  them to the conventional uppercase form (`"GET"`, `"POST"`).

  ## Examples

      iex> Monitorex.Event.normalize_method(:get)
      "GET"

      iex> Monitorex.Event.normalize_method(:post)
      "POST"

      iex> Monitorex.Event.normalize_method("GET")
      "GET"

  """
  @spec normalize_method(method :: atom() | String.t()) :: String.t()
  def normalize_method(method) when is_atom(method) do
    method |> Atom.to_string() |> String.upcase()
  end

  def normalize_method(method) when is_binary(method) do
    String.upcase(method)
  end

  @doc """
  Extracts the host from a `URI.t()` struct or a URL string.

  ## Examples

      iex> Monitorex.Event.extract_host(%URI{host: "example.com"})
      "example.com"

      iex> Monitorex.Event.extract_host("https://api.example.com/path")
      "api.example.com"

      iex> Monitorex.Event.extract_host(%URI{host: nil})
      nil

  """
  @spec extract_host(uri_or_url :: URI.t() | String.t()) :: String.t() | nil
  def extract_host(%URI{host: host}), do: host

  def extract_host(url) when is_binary(url) do
    url |> URI.parse() |> Map.get(:host)
  end
end
