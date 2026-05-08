defmodule Monitorex.AssetsTest do
  use ExUnit.Case, async: true

  alias Monitorex.Assets

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
      conn =
        :get
        |> Plug.Test.conn("/dashboard-assets/app.css")
        |> Map.put(:path_info, ["dashboard-assets", "app.css"])
        |> Assets.call(Assets.init([]))

      assert conn.status == 200
      assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/css; charset=utf-8"]
      assert conn.resp_body =~ "Monitorex Dashboard — Design System v2"
    end

    test "serves JS file" do
      conn =
        :get
        |> Plug.Test.conn("/dashboard-assets/app.js")
        |> Map.put(:path_info, ["dashboard-assets", "app.js"])
        |> Assets.call(Assets.init([]))

      assert conn.status == 200
      assert Plug.Conn.get_resp_header(conn, "content-type") == ["application/javascript; charset=utf-8"]
      assert conn.resp_body =~ "Monitorex Dashboard"
    end

    test "sets far-future cache headers" do
      conn =
        :get
        |> Plug.Test.conn("/dashboard-assets/app.css")
        |> Map.put(:path_info, ["dashboard-assets", "app.css"])
        |> Assets.call(Assets.init([]))

      cache_control = Plug.Conn.get_resp_header(conn, "cache-control")
      assert cache_control != []
      assert hd(cache_control) =~ "max-age=31536000"
    end

    test "returns 404 for unknown asset" do
      conn =
        :get
        |> Plug.Test.conn("/dashboard-assets/nonexistent.js")
        |> Map.put(:path_info, ["dashboard-assets", "nonexistent.js"])
        |> Assets.call(Assets.init([]))

      assert conn.status == 404
    end

    test "returns 404 for wrong path prefix" do
      conn =
        :get
        |> Plug.Test.conn("/other/app.css")
        |> Map.put(:path_info, ["other", "app.css"])
        |> Assets.call(Assets.init([]))

      assert conn.status == 404
    end
  end
end
