defmodule Monitorex.MountOptionsTest do
  use ExUnit.Case, async: true

  alias Monitorex.MountOptions

  describe "session/3" do
    test "returns root mount prefix when no script_name" do
      conn = %Plug.Conn{script_name: []}

      assert MountOptions.session(conn, "/dashboard-assets", "/live") == %{
               "mount_prefix" => "/",
               "assets_path" => "/dashboard-assets",
               "socket_path" => "/live"
             }
    end

    test "derives mount prefix from script_name" do
      conn = %Plug.Conn{script_name: ["monitoring"]}

      assert MountOptions.session(conn, "/dashboard-assets", "/live")["mount_prefix"] ==
               "/monitoring"
    end

    test "supports multi-segment script_name" do
      conn = %Plug.Conn{script_name: ["apps", "monitoring"]}

      assert MountOptions.session(conn, "/dashboard-assets", "/live")["mount_prefix"] ==
               "/apps/monitoring"
    end

    test "threads assets_path and socket_path" do
      conn = %Plug.Conn{script_name: []}
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
