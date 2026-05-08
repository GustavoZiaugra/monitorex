defmodule Monitorex.AuthenticationTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveView

  alias Monitorex.Authentication

  describe "on_mount/4" do
    test "grants :all access with default resolver" do
      socket = %Phoenix.LiveView.Socket{}
      session = %{}

      assert {:cont, socket} = Authentication.on_mount(:default, %{}, session, socket)
      assert socket.assigns.current_user == %{id: nil, name: "anonymous"}
      refute Map.has_key?(socket.assigns, :read_only)
    end

    test "grants :read_only access" do
      defmodule ReadOnlyResolver do
        @behaviour Monitorex.Resolver
        def resolve_user(_conn), do: %{id: 1, name: "reader"}
        def resolve_access(_user), do: :read_only
      end

      Application.put_env(:monitorex, :resolver, ReadOnlyResolver)

      socket = %Phoenix.LiveView.Socket{}
      assert {:cont, socket} = Authentication.on_mount(:default, %{}, %{}, socket)
      assert socket.assigns.read_only == true

      Application.delete_env(:monitorex, :resolver)
    end

    test "redirects on {:forbidden, path}" do
      defmodule ForbiddenResolver do
        @behaviour Monitorex.Resolver
        def resolve_user(_conn), do: %{id: 1, name: "banned"}
        def resolve_access(_user), do: {:forbidden, "/login"}
      end

      Application.put_env(:monitorex, :resolver, ForbiddenResolver)

      socket = %Phoenix.LiveView.Socket{}
      assert {:halt, socket} = Authentication.on_mount(:default, %{}, %{}, socket)
      assert elem(socket.redirected, 0) == :redirect
      assert socket.redirected |> elem(1) |> Map.get(:to) == "/login"

      Application.delete_env(:monitorex, :resolver)
    end

    test "falls back to root redirect when forbidden path is not a string" do
      defmodule BadForbiddenResolver do
        @behaviour Monitorex.Resolver
        def resolve_user(_conn), do: %{id: 1, name: "banned"}
        def resolve_access(_user), do: {:forbidden, nil}
      end

      Application.put_env(:monitorex, :resolver, BadForbiddenResolver)

      socket = %Phoenix.LiveView.Socket{}
      assert {:halt, socket} = Authentication.on_mount(:default, %{}, %{}, socket)
      assert elem(socket.redirected, 0) == :redirect
      assert socket.redirected |> elem(1) |> Map.get(:to) == "/"

      Application.delete_env(:monitorex, :resolver)
    end

    test "reads user from session when present" do
      defmodule SessionResolver do
        @behaviour Monitorex.Resolver
        def resolve_user(_conn), do: %{id: 99, name: "fallback"}
        def resolve_access(user), do: if(user["id"] == 42, do: :all, else: :read_only)
      end

      Application.put_env(:monitorex, :resolver, SessionResolver)

      socket = %Phoenix.LiveView.Socket{}
      session = %{"monitorex_user" => %{"id" => 42, "name" => "session_user"}}
      assert {:cont, socket} = Authentication.on_mount(:default, %{}, session, socket)
      assert socket.assigns.current_user == %{"id" => 42, "name" => "session_user"}

      Application.delete_env(:monitorex, :resolver)
    end
  end
end
