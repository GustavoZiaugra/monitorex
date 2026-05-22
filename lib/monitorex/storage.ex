defmodule Monitorex.Storage do
  @moduledoc """
  Read/query layer over the configured storage backend.

  All functions delegate to the active backend (ETS by default, SQLite
  when configured). This module is the single entry-point for dashboard
  pages, API, and exports.

  ## Configuration

      config :monitorex, :storage_backend, Monitorex.Storage.ETS

  Or:

      config :monitorex, :storage_backend, Monitorex.Storage.SQLite
      config :monitorex, :sqlite_path, "/var/lib/monitorex/data.db"
  """

  alias Monitorex.Event

  @default_backend Monitorex.Storage.ETS

  # ── Helpers ──

  defp backend do
    Application.get_env(:monitorex, :storage_backend, @default_backend)
  end

  # ── Outbound Queries ──

  @doc """
  Returns list of host aggregates sorted by requests descending.
  """
  @spec list_hosts() :: [map()]
  def list_hosts, do: backend().list_hosts()

  @doc """
  Returns list of endpoint aggregates for a given host.
  """
  @spec list_endpoints_for_host(String.t()) :: [map()]
  def list_endpoints_for_host(host), do: backend().list_endpoints_for_host(host)

  @doc """
  Returns most recent outbound Events with optional filtering.

  ## Options

    * `:limit` — maximum events (default: 50)
    * `:offset` — events to skip (default: 0)
    * `:status_class` — filter by status class atom
    * `:host` — filter by exact host match
  """
  @spec list_recent_outbound(keyword()) :: [Event.t()]
  def list_recent_outbound(opts \\ []), do: backend().list_recent_outbound(opts)

  # ── Inbound Queries ──

  @doc """
  Returns route aggregates sorted by requests descending.
  """
  @spec list_routes() :: [map()]
  def list_routes, do: backend().list_routes()

  @doc """
  Returns consumer aggregates sorted by requests descending.
  """
  @spec list_consumers() :: [map()]
  def list_consumers, do: backend().list_consumers()

  @doc """
  Returns most recent inbound Events with optional filtering.

  ## Options

    * `:limit` — maximum events (default: 50)
    * `:offset` — events to skip (default: 0)
    * `:status_class` — filter by status class atom
    * `:consumer` — filter by exact consumer match
    * `:route` — filter by route key (`"Method:path"`)
  """
  @spec list_recent_inbound(keyword()) :: [Event.t()]
  def list_recent_inbound(opts \\ []), do: backend().list_recent_inbound(opts)

  @doc """
  Returns consumer breakdown for a given route key.
  """
  @spec list_consumers_for_route(String.t()) :: [map()]
  def list_consumers_for_route(route_key), do: backend().list_consumers_for_route(route_key)

  @doc """
  Fetches a specific event by timestamp from either outbound or inbound tables.
  """
  @spec get_event(integer()) :: Event.t() | nil
  def get_event(timestamp) when is_integer(timestamp), do: backend().get_event(timestamp)

  # ── Count queries ──

  @doc """
  Returns count of recent outbound events matching optional filters.
  """
  @spec count_recent_outbound(keyword()) :: non_neg_integer()
  def count_recent_outbound(opts \\ []), do: backend().count_recent_outbound(opts)

  @doc """
  Returns count of recent inbound events matching optional filters.
  """
  @spec count_recent_inbound(keyword()) :: non_neg_integer()
  def count_recent_inbound(opts \\ []), do: backend().count_recent_inbound(opts)

  # ── Slow Request Queries ──

  @doc """
  Returns slow outbound events, newest first.

  ## Options

    * `:limit` — max events (default: 50)
  """
  @spec list_slow_outbound(keyword()) :: [Event.t()]
  def list_slow_outbound(opts \\ []), do: backend().list_slow_outbound(opts)

  @doc """
  Returns slow inbound events, newest first.

  ## Options

    * `:limit` — max events (default: 50)
  """
  @spec list_slow_inbound(keyword()) :: [Event.t()]
  def list_slow_inbound(opts \\ []), do: backend().list_slow_inbound(opts)
end
