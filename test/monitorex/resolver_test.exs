defmodule Monitorex.ResolverTest do
  use ExUnit.Case, async: true

  alias Monitorex.Resolver.Default

  describe "behaviour contract" do
    test "Default module implements resolve_user/1" do
      assert is_function(&Default.resolve_user/1)
    end

    test "Default module implements resolve_access/1" do
      assert is_function(&Default.resolve_access/1)
    end

    test "resolve_user/1 returns a map with id and name" do
      user = Default.resolve_user(%Plug.Conn{})
      assert is_map(user)
      assert user.id == nil
      assert user.name == "anonymous"
    end

    test "resolve_access/1 returns :all for any user" do
      assert Default.resolve_user(%Plug.Conn{}) |> Default.resolve_access() == :all
      assert Default.resolve_access(%{id: 1, name: "admin"}) == :all
      assert Default.resolve_access(nil) == :all
    end
  end

  describe "optional callbacks" do
    test "Default does not export resolve_refresh/1" do
      refute function_exported?(Default, :resolve_refresh, 1)
    end

    test "Resolver behaviour can be implemented without resolve_refresh" do
      assert is_function(&Default.resolve_user/1)
      assert is_function(&Default.resolve_access/1)
    end
  end
end
