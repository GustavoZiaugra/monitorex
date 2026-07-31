defmodule Monitorex.AssetsTest do
  use ExUnit.Case, async: true

  alias Monitorex.Assets
  alias Plug.Conn
  alias Plug.Test

  describe "hash functions" do
    test "css_hash/0 returns a 32-character hex string" do
      hash = Assets.css_hash()
      assert is_binary(hash)
      assert String.length(hash) == 32
      assert hash =~ ~r/^[a-f0-9]{32}$/
    end

    test "js_hash/0 returns a 32-character hex string" do
      hash = Assets.js_hash()
      assert is_binary(hash)
      assert String.length(hash) == 32
      assert hash =~ ~r/^[a-f0-9]{32}$/
    end

    test "hashes are deterministic" do
      assert Assets.css_hash() == Assets.css_hash()
      assert Assets.js_hash() == Assets.js_hash()
    end

    test "css and js hashes are different" do
      assert Assets.css_hash() != Assets.js_hash()
    end
  end

  describe "init/1" do
    test "returns default path without opts" do
      assert Assets.init([]) == %{at: "/dashboard-assets"}
    end

    test "returns default path even with custom opts" do
      assert Assets.init(at: "/custom-assets") == %{at: "/dashboard-assets"}
    end
  end

  describe "call/2" do
    test "serves CSS file" do
      base_conn = Test.conn(:get, "/dashboard-assets/app.css")

      conn =
        base_conn
        |> Map.put(:path_info, ["dashboard-assets", "app.css"])
        |> Assets.call(Assets.init([]))

      assert conn.status == 200
      assert Conn.get_resp_header(conn, "content-type") == ["text/css; charset=utf-8"]
      assert conn.resp_body =~ "tailwindcss"
      assert conn.resp_body =~ "--sidebar-width"
    end

    test "serves JS file" do
      base_conn = Test.conn(:get, "/dashboard-assets/app.js")

      conn =
        base_conn
        |> Map.put(:path_info, ["dashboard-assets", "app.js"])
        |> Assets.call(Assets.init([]))

      assert conn.status == 200

      assert Conn.get_resp_header(conn, "content-type") == [
               "application/javascript; charset=utf-8"
             ]

      assert conn.resp_body =~ "nav-toggle"
    end

    test "sets far-future cache headers" do
      base_conn = Test.conn(:get, "/dashboard-assets/app.css")

      conn =
        base_conn
        |> Map.put(:path_info, ["dashboard-assets", "app.css"])
        |> Assets.call(Assets.init([]))

      cache_control = Conn.get_resp_header(conn, "cache-control")
      assert cache_control != []
      assert hd(cache_control) =~ "max-age=31536000"
    end

    test "returns 404 for unknown asset" do
      base_conn = Test.conn(:get, "/dashboard-assets/nonexistent.js")

      conn =
        base_conn
        |> Map.put(:path_info, ["dashboard-assets", "nonexistent.js"])
        |> Assets.call(Assets.init([]))

      assert conn.status == 404
    end

    test "serves assets under any leading path prefix" do
      base_conn = Test.conn(:get, "/other/app.css")

      conn =
        base_conn
        |> Map.put(:path_info, ["other", "app.css"])
        |> Assets.call(Assets.init([]))

      assert conn.status == 200
      assert Conn.get_resp_header(conn, "content-type") == ["text/css; charset=utf-8"]
    end

    test "serves assets under a custom assets_path" do
      base_conn = Test.conn(:get, "/custom-assets/app.css")

      conn =
        base_conn
        |> Map.put(:path_info, ["custom-assets", "app.css"])
        |> Assets.call(Assets.init([]))

      assert conn.status == 200
      assert Conn.get_resp_header(conn, "content-type") == ["text/css; charset=utf-8"]
    end

    test "serves CSS when mounted under an endpoint script_name prefix" do
      base_conn = Test.conn(:get, "/monitoring/dashboard-assets/app.css")

      conn =
        base_conn
        |> Map.put(:script_name, ["monitoring"])
        |> Map.put(:path_info, ["monitoring", "dashboard-assets", "app.css"])
        |> Assets.call(Assets.init([]))

      assert conn.status == 200
      assert conn.resp_body =~ "tailwindcss"
    end

    test "serves JS when mounted under an endpoint script_name prefix" do
      base_conn = Test.conn(:get, "/monitoring/dashboard-assets/app.js")

      conn =
        base_conn
        |> Map.put(:script_name, ["monitoring"])
        |> Map.put(:path_info, ["monitoring", "dashboard-assets", "app.js"])
        |> Assets.call(Assets.init([]))

      assert conn.status == 200
      assert conn.resp_body =~ "nav-toggle"
    end

    test "serves CSS when mounted under a router scope prefix" do
      base_conn = Test.conn(:get, "/monitoring/dashboard-assets/app.css")

      conn =
        base_conn
        |> Map.put(:path_info, ["monitoring", "dashboard-assets", "app.css"])
        |> Assets.call(Assets.init([]))

      assert conn.status == 200
    end

    test "returns 404 when asset mount is not at the end of the path" do
      base_conn = Test.conn(:get, "/app.css/dashboard-assets")

      conn =
        base_conn
        |> Map.put(:path_info, ["app.css", "dashboard-assets"])
        |> Assets.call(Assets.init([]))

      assert conn.status == 404
    end
  end
end
