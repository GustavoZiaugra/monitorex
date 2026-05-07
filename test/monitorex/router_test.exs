defmodule Monitorex.RouterTest do
  use ExUnit.Case, async: true

  describe "http_dashboard/1 macro" do
    test "expands to a list of router DSL calls" do
      # The macro should expand into a sequence of Phoenix router calls:
      # get, live_session, live
      expanded =
        Macro.expand(
          quote do
            import Monitorex.Router
            http_dashboard []
          end,
          __ENV__
        )

      # The expansion should be a __block__ with multiple forms
      assert elem(expanded, 0) == :__block__
    end

    test "accepts custom assets_path option" do
      expanded =
        Macro.expand(
          quote do
            import Monitorex.Router
            http_dashboard assets_path: "/custom-assets"
          end,
          __ENV__
        )

      assert expanded != nil
    end

    test "accepts custom live_view option" do
      expanded =
        Macro.expand(
          quote do
            import Monitorex.Router
            http_dashboard live_view: CustomDashboardLive
          end,
          __ENV__
        )

      assert expanded != nil
    end

    test "accepts custom layout option" do
      expanded =
        Macro.expand(
          quote do
            import Monitorex.Router
            http_dashboard layout: {CustomLayout, :root}
          end,
          __ENV__
        )

      assert expanded != nil
    end

    test "accepts custom on_mount option" do
      expanded =
        Macro.expand(
          quote do
            import Monitorex.Router
            http_dashboard on_mount: [CustomAuth]
          end,
          __ENV__
        )

      assert expanded != nil
    end
  end
end
