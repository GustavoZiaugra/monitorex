defmodule Mix.Tasks.Monitorex.InstallTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  @router """
  defmodule TestWeb.Router do
    use Phoenix.Router

    pipeline :browser do
      plug :accepts, ["html"]
      plug :fetch_session
      plug :fetch_live_flash
      plug :protect_from_forgery
    end

    scope "/", TestWeb do
      pipe_through :browser
      get "/", PageController, :home
    end
  end
  """

  @mix_exs """
  defmodule Test.MixProject do
    use Mix.Project

    def project do
      [
        app: :test,
        version: "0.1.0",
        elixir: "~> 1.15",
        deps: deps()
      ]
    end

    def application do
      [extra_applications: [:logger]]
    end

    defp deps do
      [
        {:phoenix, "~> 1.8"},
        {:tesla, "~> 1.4"},
        {:finch, "~> 0.16"}
      ]
    end
  end
  """

  defp project(mix_exs \\ @mix_exs, config \\ "import Config\n", router \\ @router) do
    test_project()
    |> replace_file("mix.exs", mix_exs)
    |> replace_file("config/config.exs", config)
    |> replace_file("lib/test_web/router.ex", router)
  end

  defp replace_file(igniter, path, contents) do
    Igniter.create_or_update_elixir_file(igniter, path, contents, fn zipper ->
      {:ok, Igniter.Code.Common.replace_code(zipper, contents)}
    end)
  end

  defp run_install(igniter, argv \\ ["--yes"]) do
    Igniter.compose_task(igniter, Mix.Tasks.Monitorex.Install, argv)
  end

  defp file_content(igniter, path) do
    {:ok, source} = Rewrite.source(igniter.rewrite, path)
    source |> Rewrite.Source.get(:content)
  end

  describe "install" do
    test "mounts the dashboard, configures sources, and emits the straightforward mount" do
      igniter =
        project()
        |> run_install()

      router = file_content(igniter, "lib/test_web/router.ex")

      assert router =~ ~s|scope "/monitoring" do|
      assert router =~ "pipe_through(:monitoring)"
      assert router =~ "http_dashboard(api_path: false)"
      assert router =~ "import Monitorex.Router"

      config = file_content(igniter, "config/config.exs")
      assert config =~ "config :monitorex, sources: [:tesla, :finch, :phoenix]"
    end

    test "detects finch adapter dedup and sets clients" do
      config = """
      import Config

      config :tesla,
        adapter: {Tesla.Adapter.Finch, name: MyFinch}
      """

      igniter =
        project(@mix_exs, config)
        |> run_install()

      config = file_content(igniter, "config/config.exs")

      assert config =~
               "config :monitorex, sources: [:tesla, :finch, :phoenix], clients: [:tesla, :finch]"
    end

    test "does not enable sources for libraries that are not deps" do
      mix_exs = """
      defmodule Test.MixProject do
        use Mix.Project

        def project do
          [
            app: :test,
            version: "0.1.0",
            elixir: "~> 1.15",
            deps: deps()
          ]
        end

        def application do
          [extra_applications: [:logger]]
        end

        defp deps do
          [
            {:phoenix, "~> 1.8"}
          ]
        end
      end
      """

      igniter =
        project(mix_exs)
        |> run_install()

      config = file_content(igniter, "config/config.exs")
      assert config =~ "config :monitorex, sources: [:phoenix]"
      refute config =~ ":tesla"
      refute config =~ ":finch"
      refute config =~ ":req"
    end

    test "adds req_telemetry when req is present but req_telemetry is absent" do
      mix_exs = """
      defmodule Test.MixProject do
        use Mix.Project

        def project do
          [
            app: :test,
            version: "0.1.0",
            elixir: "~> 1.15",
            deps: deps()
          ]
        end

        def application do
          [extra_applications: [:logger]]
        end

        defp deps do
          [
            {:phoenix, "~> 1.8"},
            {:req, "~> 0.5"}
          ]
        end
      end
      """

      igniter =
        project(mix_exs)
        |> run_install()

      mix = file_content(igniter, "mix.exs")
      assert mix =~ ~s|{:req_telemetry, "~> 0.1"}|

      config = file_content(igniter, "config/config.exs")
      assert config =~ "config :monitorex, sources: [:req, :phoenix]"
    end

    test "does not add req_telemetry when it is already a dep" do
      mix_exs = """
      defmodule Test.MixProject do
        use Mix.Project

        def project do
          [
            app: :test,
            version: "0.1.0",
            elixir: "~> 1.15",
            deps: deps()
          ]
        end

        def application do
          [extra_applications: [:logger]]
        end

        defp deps do
          [
            {:phoenix, "~> 1.8"},
            {:req, "~> 0.5"},
            {:req_telemetry, "~> 0.1"}
          ]
        end
      end
      """

      igniter =
        project(mix_exs)
        |> run_install()

      mix = file_content(igniter, "mix.exs")
      assert length(String.split(mix, "req_telemetry")) == 2
    end

    test "warns when mount path collides with an existing scope" do
      router_with_scope = """
      defmodule TestWeb.Router do
        use Phoenix.Router

        pipeline :browser do
          plug :accepts, ["html"]
        end

        scope "/monitoring" do
          pipe_through :browser
          get "/other", PageController, :home
        end
      end
      """

      igniter =
        project(@mix_exs, "import Config\n", router_with_scope)
        |> run_install()

      assert Enum.any?(igniter.warnings, &(&1 =~ "collides with an existing scope"))
    end

    test "warns when router already has a scope /api" do
      router_with_api = """
      defmodule TestWeb.Router do
        use Phoenix.Router

        pipeline :browser do
          plug :accepts, ["html"]
        end

        scope "/api" do
          pipe_through :browser
          get "/users", UserController, :index
        end
      end
      """

      igniter =
        project(@mix_exs, "import Config\n", router_with_api)
        |> run_install()

      assert Enum.any?(igniter.warnings, &(&1 =~ "existing `scope \"/api\"`"))
    end

    test "uses a dedicated :monitoring pipeline without protect_from_forgery" do
      router_without_pipeline = """
      defmodule TestWeb.Router do
        use Phoenix.Router

        scope "/", TestWeb do
          get "/", PageController, :home
        end
      end
      """

      igniter =
        project(@mix_exs, "import Config\n", router_without_pipeline)
        |> run_install()

      router = file_content(igniter, "lib/test_web/router.ex")

      assert router =~ "pipeline :monitoring do"
      assert router =~ ~s|plug(:accepts, ["html"])|
      assert router =~ "plug(:fetch_session)"
      assert router =~ "plug(:fetch_live_flash)"
      refute router =~ "protect_from_forgery"
      assert router =~ "pipe_through(:monitoring)"
    end
  end
end
