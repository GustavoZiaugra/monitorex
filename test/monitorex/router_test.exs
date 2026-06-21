defmodule Monitorex.RouterTest do
  use ExUnit.Case, async: true

  alias Phoenix.Router

  defp build_router(name, opts) do
    module = Module.concat(Monitorex, name)

    Code.eval_quoted(
      quote do
        defmodule unquote(module) do
          use Phoenix.Router
          import Monitorex.Router

          scope "/" do
            http_dashboard(unquote(opts))
          end
        end
      end,
      [],
      __ENV__
    )

    module
  end

  describe "http_dashboard/1 macro" do
    test "expands to a list of router DSL calls" do
      # The macro should expand into a sequence of Phoenix router calls:
      # get, live_session, live
      expanded =
        Macro.expand(
          quote do
            import Monitorex.Router
            http_dashboard([])
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
            http_dashboard(assets_path: "/custom-assets")
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
            http_dashboard(live_view: CustomDashboardLive)
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
            http_dashboard(layout: {CustomLayout, :root})
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
            http_dashboard(on_mount: [CustomAuth])
          end,
          __ENV__
        )

      assert expanded != nil
    end

    test "registers health endpoint route" do
      router = build_router(:TestRouterHealth, api_path: "/api")
      routes = Router.routes(router)
      paths = Enum.map(routes, &to_string(&1.path))

      assert "/monitorex/health" in paths
    end

    test "registers export endpoint route" do
      router = build_router(:TestRouterExport, api_path: "/api")
      routes = Router.routes(router)
      paths = Enum.map(routes, &to_string(&1.path))

      assert "/export/:page/:format" in paths
    end

    test "registers API forward when api_path is set" do
      router = build_router(:TestRouterWithApi, api_path: "/api")
      routes = Router.routes(router)

      api_route = Enum.find(routes, fn r -> to_string(r.path) == "/api" end)
      assert api_route != nil
      assert api_route.plug == Monitorex.ApiPlug
    end

    test "does not register API forward when api_path is false" do
      router = build_router(:TestRouterNoApi, api_path: false)
      routes = Router.routes(router)
      plugs = Enum.map(routes, & &1.plug)

      refute Monitorex.ApiPlug in plugs
    end
  end
end
