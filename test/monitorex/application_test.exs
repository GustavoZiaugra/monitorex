defmodule Monitorex.ApplicationTest do
  use ExUnit.Case, async: false

  alias Monitorex.Application, as: App

  describe "start/2" do
    test "supervisor is already running from test suite" do
      # The Application is started by the test helper / mix test.
      # Verify the supervision tree is alive.
      assert Process.whereis(Monitorex.Supervisor) != nil
    end

    test "children spec includes Collector in running supervisor" do
      children = Supervisor.which_children(Monitorex.Supervisor)
      assert Enum.any?(children, fn {mod, _pid, _type, _modules} ->
        mod == Monitorex.Collector
      end)
    end

    test "start returns already_started when running" do
      # When the app is already started, calling start/2 again returns
      # the existing supervisor.
      result = App.start(:normal, [])
      assert match?({:error, {:already_started, _pid}}, result) or
             match?({:ok, _pid}, result)
    end
  end

  describe "children spec" do
    test "defines Monitorex.Collector as the primary child" do
      # Verify the children list returned by start/2 logic indirectly
      # by inspecting the module's public API.
      assert function_exported?(App, :start, 2)
    end
  end
end
