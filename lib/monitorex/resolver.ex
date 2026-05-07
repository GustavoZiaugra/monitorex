defmodule Monitorex.Resolver do
  @moduledoc """
  Behaviour for resolving the current user and their access level in the
  Monitorex dashboard.

  Implement this module in your application and configure it via:

      config :monitorex, :resolver, MyApp.MonitorexResolver

  ## Callbacks

    * `resolve_user/1` — receives a `Plug.Conn.t()` and returns a user struct
      (any shape). The user is stored in the LiveView socket assigns as
      `:current_user`.

    * `resolve_access/1` — receives the user struct returned by `resolve_user/1`
      and returns one of:
        * `:all` — full access (read + write)
        * `:read_only` — read-only access
        * `{:forbidden, path}` — redirect user to the given path

    * `resolve_refresh/1` — optional. Receives a `Plug.Conn.t()` and returns a
      (possibly modified) conn. Called after access is resolved, useful for
      extending the session lifetime.
  """

  @doc """
  Resolves the current user from the Plug connection.
  Returns a user struct of any shape.
  """
  @callback resolve_user(conn :: Plug.Conn.t()) :: map()

  @doc """
  Resolves the access level for the given user.

  Returns `:all`, `:read_only`, or `{:forbidden, redirect_path}`.
  """
  @callback resolve_access(user :: struct()) :: :all | :read_only | {:forbidden, String.t()}

  @doc """
  Optional callback to refresh the connection (e.g., extend session).
  """
  @callback resolve_refresh(conn :: Plug.Conn.t()) :: Plug.Conn.t()

  @optional_callbacks resolve_refresh: 1
end
