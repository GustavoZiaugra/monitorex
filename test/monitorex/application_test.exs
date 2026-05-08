defmodule Monitorex.ApplicationTest do
  use ExUnit.Case, async: false

  describe "application lifecycle" do
    test "Monitorex.Supervisor is running" do
      assert Process.whereis(Monitorex.Supervisor) != nil,
             "Expected Monitorex.Supervisor to be registered"
    end

    test "children spec includes Collector" do
      sup = Process.whereis(Monitorex.Supervisor)
      assert sup != nil

      children = Supervisor.which_children(sup)
      assert Enum.any?(children, fn {mod, _pid, _type, _modules} ->
        mod == Monitorex.Collector
      end), "Collector not found in supervisor children"
    end
  end
end
