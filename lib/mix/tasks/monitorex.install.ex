if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Monitorex.Install do
    @shortdoc "Installs Monitorex into a Phoenix application"

    @moduledoc """
    Installs Monitorex into a Phoenix application.

    This task is run automatically when you add Monitorex with `mix igniter.install monitorex`.

    It detects from the host application's AST:

      * which sources to enable (`:tesla`, `:finch` and/or `:req`, based on the dep tree)
      * whether dedup is needed (a `config :tesla, adapter: {Tesla.Adapter.Finch, _}` sets
        `clients: [:tesla, :finch]`)
      * whether an existing `scope "/api"` in the router makes the built-in REST API
        redundant (it is disabled with `api_path: false` either way)
      * where to mount (a `--path` option, defaulting to `/monitoring`, warned about when it
        collides with an existing scope)
      * whether `:req_telemetry` should be added (`:req` present but `:req_telemetry` absent)

    The mount uses a dedicated `:monitoring` pipeline — deliberately **not** your
    `:browser` pipeline. `:browser` includes `protect_from_forgery`, which rejects the
    cross-origin `app.js` asset request with a 403; the `:monitoring` pipeline omits it
    (see the installation guide).

    ## Options

    * `--path` - the path to mount the dashboard at (default: `/monitoring`)
    * `--yes` - automatically answer yes to all prompts
    """

    use Igniter.Mix.Task

    @default_mount_path "/monitoring"
    @config_files ["config.exs", "runtime.exs", "dev.exs", "prod.exs", "test.exs"]

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :monitorex,
        positional: [],
        schema: [
          path: :string,
          yes: :boolean
        ],
        defaults: [path: @default_mount_path],
        aliases: [],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      mount_path = mount_path(igniter)

      {igniter, router} = Igniter.Libs.Phoenix.select_router(igniter)

      if router == nil do
        Igniter.add_issue(igniter, """
        Could not find a Phoenix router to install Monitorex into.

        Monitorex is mounted into an existing Phoenix router. Add a router using
        `use Phoenix.Router` (or your application's `use <App>Web, :router`) and
        re-run `mix igniter.install monitorex`.
        """)
      else
        igniter
        |> maybe_warn_mount_collision(router, mount_path)
        |> maybe_warn_api_scope(router)
        |> add_import(router)
        |> ensure_pipeline(router)
        |> add_mount_scope(router, mount_path)
        |> configure_sources()
        |> maybe_configure_clients()
        |> maybe_add_req_telemetry()
      end
    end

    defp mount_path(igniter) do
      options = igniter.args.options

      cond do
        options[:path] ->
          options[:path]

        igniter.assigns[:test_mode?] || options[:yes] ->
          @default_mount_path

        true ->
          case Mix.shell().prompt("Mount Monitorex at which path? [#{@default_mount_path}]") do
            "" -> @default_mount_path
            path -> path
          end
      end
    end

    defp maybe_warn_mount_collision(igniter, router, mount_path) do
      if router_has_scope?(igniter, router, mount_path) do
        Igniter.add_warning(igniter, """
        The mount path `#{mount_path}` collides with an existing scope in #{inspect(router)}.

        Monitorex will be mounted into that path anyway. If you intended a different
        mount path, re-run with `--path /some/other/path`.
        """)
      else
        igniter
      end
    end

    defp maybe_warn_api_scope(igniter, router) do
      if router_has_scope?(igniter, router, "/api") do
        Igniter.add_warning(igniter, """
        An existing `scope "/api"` was detected in #{inspect(router)}.

        Monitorex's built-in REST API is disabled (`http_dashboard api_path: false`) so
        it does not conflict with your existing `/api` routes. To enable the Monitorex
        REST API, mount it in a separate scope:

            scope "/monitoring/api" do
              forward "/", Monitorex.ApiPlug
            end
        """)
      else
        igniter
      end
    end

    defp router_has_scope?(igniter, router, path) do
      with {:ok, {_igniter, _source, zipper}} <-
             Igniter.Project.Module.find_module(igniter, router) do
        Igniter.Code.Function.move_to_function_call(zipper, :scope, [1, 2, 3], fn fc ->
          Igniter.Code.Function.argument_equals?(fc, 0, path)
        end)
        |> case do
          {:ok, _} -> true
          _ -> false
        end
      else
        _ -> false
      end
    end

    defp add_import(igniter, router) do
      Igniter.Project.Module.find_and_update_module(igniter, router, fn zipper ->
        case Igniter.Libs.Phoenix.move_to_router_use(igniter, zipper) do
          {:ok, use_zipper} ->
            {:ok, Igniter.Code.Common.add_code(use_zipper, "import Monitorex.Router")}

          :error ->
            :error
        end
      end)
      |> case do
        {:ok, igniter} -> igniter
        {:error, igniter} -> igniter
      end
    end

    defp ensure_pipeline(igniter, router) do
      {igniter, has_pipeline?} = Igniter.Libs.Phoenix.has_pipeline(igniter, router, :monitoring)

      if has_pipeline? do
        igniter
      else
        Igniter.Libs.Phoenix.add_pipeline(
          igniter,
          :monitoring,
          """
          plug :accepts, ["html"]
          plug :fetch_session
          plug :fetch_live_flash
          """, router: router)
      end
    end

    defp add_mount_scope(igniter, router, mount_path) do
      Igniter.Libs.Phoenix.add_scope(
        igniter,
        mount_path,
        """
        pipe_through :monitoring
        http_dashboard(api_path: false)
        """, router: router, placement: :after)
    end

    defp configure_sources(igniter) do
      sources =
        [:tesla, :finch, :req]
        |> Enum.filter(&Igniter.Project.Deps.has_dep?(igniter, &1))
        |> Kernel.++([:phoenix])

      Igniter.Project.Config.configure(igniter, "config.exs", :monitorex, [:sources], sources)
    end

    defp maybe_configure_clients(igniter) do
      if tesla_uses_finch_adapter?(igniter) do
        Igniter.Project.Config.configure(igniter, "config.exs", :monitorex, [:clients], [
          :tesla,
          :finch
        ])
      else
        igniter
      end
    end

    defp tesla_uses_finch_adapter?(igniter) do
      Enum.any?(@config_files, fn file ->
        case config_zipper(igniter, file) do
          nil -> false
          zipper -> zipper_has_tesla_finch_adapter?(zipper)
        end
      end)
    end

    defp config_zipper(igniter, file_name) do
      config_dir = igniter |> Igniter.Project.Application.config_path() |> Path.dirname()
      path = Path.join(config_dir, file_name)
      igniter = Igniter.include_existing_file(igniter, path, required?: false)

      case Rewrite.source(igniter.rewrite, path) do
        {:ok, source} ->
          source
          |> Rewrite.Source.get(:quoted)
          |> Sourceror.Zipper.zip()

        _ ->
          nil
      end
    end

    defp zipper_has_tesla_finch_adapter?(zipper) do
      with {:ok, _zipper} <-
             Igniter.Code.Function.move_to_function_call_in_current_scope(
               zipper,
               :config,
               [
                 2,
                 3
               ],
               fn fc ->
                 Igniter.Code.Function.argument_equals?(fc, 0, :tesla) &&
                   config_call_has_finch_adapter?(fc)
               end
             ) do
        true
      else
        _ ->
          false
      end
    end

    defp config_call_has_finch_adapter?(fc) do
      if Igniter.Code.Function.argument_equals?(fc, 1, :adapter) do
        # 3-arg form: config :tesla, :adapter, value
        with {:ok, value} <- Igniter.Code.Function.move_to_nth_argument(fc, 2) do
          finch_adapter_literal?(value)
        else
          _ -> false
        end
      else
        # 2-arg keyword form: config :tesla, adapter: value
        with {:ok, kw} <- Igniter.Code.Function.move_to_nth_argument(fc, 1),
             {:ok, value} <- Igniter.Code.Keyword.get_key(kw, :adapter) do
          finch_adapter_literal?(value)
        else
          _ -> false
        end
      end
    end

    defp finch_adapter_literal?(zipper) do
      case Igniter.Code.Common.expand_literal(zipper) do
        {:ok, {Tesla.Adapter.Finch, _}} -> true
        {:ok, Tesla.Adapter.Finch} -> true
        _ -> false
      end
    end

    defp maybe_add_req_telemetry(igniter) do
      if Igniter.Project.Deps.has_dep?(igniter, :req) and
           not Igniter.Project.Deps.has_dep?(igniter, :req_telemetry) do
        if yes?(
             igniter,
             "Add {:req_telemetry, \"~> 0.1\"} to enable Req telemetry for Monitorex?"
           ) do
          Igniter.Project.Deps.add_dep(igniter, {:req_telemetry, "~> 0.1"})
        else
          igniter
        end
      else
        igniter
      end
    end

    defp yes?(igniter, prompt) do
      igniter.args.options[:yes] || igniter.assigns[:test_mode?] || Igniter.Util.IO.yes?(prompt)
    end
  end
else
  defmodule Mix.Tasks.Monitorex.Install do
    @moduledoc false
    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'monitorex.install' requires igniter to be installed.

      Add {:igniter, "~> 0.6"} to your dependencies and run `mix igniter.install monitorex`,
      or follow the manual installation steps in the Monitorex README.
      """)

      exit({:shutdown, 1})
    end
  end
end
