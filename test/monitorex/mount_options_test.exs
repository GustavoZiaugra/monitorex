defmodule Monitorex.MountOptionsTest do
  use ExUnit.Case, async: true

  alias Monitorex.MountOptions

  describe "session/3" do
    test "returns root mount prefix when at root scope" do
      conn = %Plug.Conn{script_name: [], path_info: ["timeline"], path_params: %{"page" => "timeline"}}

      assert MountOptions.session(conn, "/dashboard-assets", "/live") == %{
               "mount_prefix" => "/",
               "assets_path" => "/dashboard-assets",
               "socket_path" => "/live"
             }
    end

    test "returns root mount prefix for the index route at root scope" do
      conn = %Plug.Conn{script_name: [], path_info: [], path_params: %{}}

      assert MountOptions.session(conn, "/dashboard-assets", "/live")["mount_prefix"] == "/"
    end

    test "derives mount prefix from a router scope path" do
      conn = %Plug.Conn{
        script_name: [],
        path_info: ["monitoring", "timeline"],
        path_params: %{"page" => "timeline"}
      }

      assert MountOptions.session(conn, "/dashboard-assets", "/live")["mount_prefix"] ==
               "/monitoring"
    end

    test "derives mount prefix for the index route under a scope path" do
      conn = %Plug.Conn{script_name: [], path_info: ["monitoring"], path_params: %{}}

      assert MountOptions.session(conn, "/dashboard-assets", "/live")["mount_prefix"] ==
               "/monitoring"
    end

    test "supports multi-segment scope paths" do
      conn = %Plug.Conn{
        script_name: [],
        path_info: ["apps", "monitoring", "timeline"],
        path_params: %{"page" => "timeline"}
      }

      assert MountOptions.session(conn, "/dashboard-assets", "/live")["mount_prefix"] ==
               "/apps/monitoring"
    end

    test "handles host/route detail pages under a scope path" do
      conn = %Plug.Conn{
        script_name: [],
        path_info: ["monitoring", "host", "api.example.com"],
        path_params: %{"page" => "host", "host" => "api.example.com"}
      }

      assert MountOptions.session(conn, "/dashboard-assets", "/live")["mount_prefix"] ==
               "/monitoring"
    end

    test "combines endpoint script_name with scope path" do
      conn = %Plug.Conn{
        script_name: ["monitoring"],
        path_info: ["timeline"],
        path_params: %{"page" => "timeline"}
      }

      assert MountOptions.session(conn, "/dashboard-assets", "/live")["mount_prefix"] ==
               "/monitoring"
    end

    test "threads assets_path and socket_path" do
      conn = %Plug.Conn{script_name: [], path_info: [], path_params: %{}}
      session = MountOptions.session(conn, "/custom-assets", "/ws/live")

      assert session["assets_path"] == "/custom-assets"
      assert session["socket_path"] == "/ws/live"
    end
  end

  describe "on_mount/4" do
    test "assigns defaults when session has no mount options" do
      socket = %Phoenix.LiveView.Socket{}
      assert {:cont, socket} = MountOptions.on_mount(:default, %{}, %{}, socket)

      assert socket.assigns.mount_prefix == "/"
      assert socket.assigns.assets_path == "/dashboard-assets"
      assert socket.assigns.socket_path == "/live"
    end

    test "assigns values from the session" do
      socket = %Phoenix.LiveView.Socket{}

      session = %{
        "mount_prefix" => "/monitoring",
        "assets_path" => "/custom-assets",
        "socket_path" => "/ws/live"
      }

      assert {:cont, socket} = MountOptions.on_mount(:default, %{}, session, socket)

      assert socket.assigns.mount_prefix == "/monitoring"
      assert socket.assigns.assets_path == "/custom-assets"
      assert socket.assigns.socket_path == "/ws/live"
    end
  end
end
