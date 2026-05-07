defmodule Monitorex.Resolver.Default do
  @moduledoc false
  @behaviour Monitorex.Resolver

  @impl true
  def resolve_user(_conn), do: %{id: nil, name: "anonymous"}

  @impl true
  def resolve_access(_user), do: :all
end
