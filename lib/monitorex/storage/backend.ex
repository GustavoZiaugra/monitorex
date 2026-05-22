defmodule Monitorex.Storage.Backend do
  @moduledoc """
  Behaviour for Monitorex storage backends.

  Implementations handle both writing telemetry events and reading/querying
  stored data. The Collector writes events through the backend; the Storage
  module reads through it.

  ## Configuring the backend

      config :monitorex, :storage_backend, Monitorex.Storage.ETS

  Or for SQLite:

      config :monitorex, :storage_backend, Monitorex.Storage.SQLite
      config :monitorex, :sqlite_path, "/var/lib/monitorex/data.db"
  """

  alias Monitorex.Event

  # ── Write callbacks ──

  @doc "Record a single telemetry event."
  @callback record_event(Event.t()) :: :ok

  @doc "Prune old data (called during Collector cleanup cycle)."
  @callback prune() :: :ok

  # ── Read callbacks ──

  @doc "List all host aggregates, sorted by requests descending."
  @callback list_hosts() :: [map()]

  @doc "List endpoint aggregates for a given host."
  @callback list_endpoints_for_host(String.t()) :: [map()]

  @doc "List recent outbound events with optional filtering."
  @callback list_recent_outbound(keyword()) :: [Event.t()]

  @doc "List route aggregates, sorted by requests descending."
  @callback list_routes() :: [map()]

  @doc "List consumer aggregates, sorted by requests descending."
  @callback list_consumers() :: [map()]

  @doc "List recent inbound events with optional filtering."
  @callback list_recent_inbound(keyword()) :: [Event.t()]

  @doc "List consumer breakdown for a route key."
  @callback list_consumers_for_route(String.t()) :: [map()]

  @doc "Fetch a specific event by timestamp."
  @callback get_event(integer()) :: Event.t() | nil

  @doc "Count recent outbound events matching filters."
  @callback count_recent_outbound(keyword()) :: non_neg_integer()

  @doc "Count recent inbound events matching filters."
  @callback count_recent_inbound(keyword()) :: non_neg_integer()

  @doc "List slow outbound events."
  @callback list_slow_outbound(keyword()) :: [Event.t()]

  @doc "List slow inbound events."
  @callback list_slow_inbound(keyword()) :: [Event.t()]
end
