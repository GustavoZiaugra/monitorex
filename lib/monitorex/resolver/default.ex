defmodule Monitorex.Resolver.Default do
  @moduledoc """
  Default resolver implementation that grants unrestricted access.

  Used when no custom `Monitorex.Resolver` is configured.
  Returns `:all` for every user, allowing full dashboard access.
  """
  @behaviour Monitorex.Resolver

  @impl true
  @doc """
  Returns a default anonymous user map.

  Always returns `%{id: nil, name: "anonymous"}` regardless of the connection.
  """
  def resolve_user(_conn), do: %{id: nil, name: "anonymous"}

  @impl true
  @doc """
  Grants unrestricted access.

  Always returns `:all`, allowing every request through.
  """
  def resolve_access(_user), do: :all
end
