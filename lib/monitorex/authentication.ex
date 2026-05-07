defmodule Monitorex.Authentication do
  @moduledoc """
  Phoenix LiveView `on_mount` hook for the Monitorex dashboard.

  Reads the current user from the session (placed there by a Plug that calls
  `resolve_user/1`), calls `resolve_access/1` on the configured resolver, and
  enforces the returned access level.

  ## Configuration

      config :monitorex, :resolver, MyApp.MonitorexResolver

  If no resolver is configured, a default that grants `:all` access is used.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  @doc false
  def on_mount(:default, _params, session, socket) do
    resolver = Application.get_env(:monitorex, :resolver, Monitorex.Resolver.Default)

    user =
      case session do
        %{"monitorex_user" => %{} = user} -> user
        _ -> resolver.resolve_user(%Plug.Conn{})
      end

    socket = assign(socket, :current_user, user)

    case resolver.resolve_access(user) do
      :all ->
        {:cont, socket}

      :read_only ->
        {:cont, assign(socket, :read_only, true)}

      {:forbidden, path} when is_binary(path) ->
        {:halt, redirect(socket, to: path)}

      {:forbidden, _path} ->
        {:halt, redirect(socket, to: "/")}
    end
  end
end
