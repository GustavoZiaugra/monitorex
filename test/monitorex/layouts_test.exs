defmodule Monitorex.LayoutsTest do
  use ExUnit.Case, async: true
  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Monitorex.Assets
  alias Monitorex.Layouts

  describe "root/1" do
    test "renders HTML document with doctype and title" do
      assigns = %{inner_content: "<div>content</div>", flash: %{}}

      html =
        rendered_to_string(~H"""
        <Layouts.root inner_content={@inner_content} flash={@flash} />
        """)

      assert html =~ "<!DOCTYPE html>"
      assert html =~ "<title>Monitorex</title>"
      assert html =~ "Monitorex"
    end

    test "includes versioned CSS and JS asset links" do
      assigns = %{inner_content: "", flash: %{}}

      html =
        rendered_to_string(~H"""
        <Layouts.root inner_content={@inner_content} flash={@flash} />
        """)

      assert html =~ "/dashboard-assets/app.css?v=#{Assets.css_hash()}"
      assert html =~ "/dashboard-assets/app.js?v=#{Assets.js_hash()}"
      refute html =~ ~s{href="/dashboard-assets/app.css"}
      refute html =~ ~s{href="/dashboard-assets/app.js"}
    end

    test "renders csrf token meta" do
      assigns = %{inner_content: "", flash: %{}}

      html =
        rendered_to_string(~H"""
        <Layouts.root inner_content={@inner_content} flash={@flash} />
        """)

      assert html =~ ~s{<meta name="csrf-token" content=}
    end

    test "renders socket path meta with default value" do
      assigns = %{inner_content: "", flash: %{}}

      html =
        rendered_to_string(~H"""
        <Layouts.root inner_content={@inner_content} flash={@flash} />
        """)

      assert html =~ ~s{<meta name="monitorex-socket-path" content="/live"}
    end

    test "uses mount prefix for asset links and navigation links" do
      assigns = %{inner_content: "", flash: %{}, mount_prefix: "/monitoring"}

      html =
        rendered_to_string(~H"""
        <Layouts.root inner_content={@inner_content} flash={@flash} mount_prefix={@mount_prefix} />
        """)

      assert html =~ "/monitoring/dashboard-assets/app.css?v=#{Assets.css_hash()}"
      assert html =~ "/monitoring/dashboard-assets/app.js?v=#{Assets.js_hash()}"
      assert html =~ ~s{href="/monitoring/"}
      assert html =~ ~s{href="/monitoring/outbound_recent"}
      assert html =~ ~s{href="/monitoring/inbound_consumers"}
      assert html =~ ~s{href="/monitoring/cluster"}
      refute html =~ ~s{href="/outbound_recent"}
    end

    test "uses custom assets path for asset links" do
      assigns = %{inner_content: "", flash: %{}, assets_path: "/custom-assets"}

      html =
        rendered_to_string(~H"""
        <Layouts.root inner_content={@inner_content} flash={@flash} assets_path={@assets_path} />
        """)

      assert html =~ "/custom-assets/app.css?v=#{Assets.css_hash()}"
      assert html =~ "/custom-assets/app.js?v=#{Assets.js_hash()}"
    end

    test "uses custom socket path meta value" do
      assigns = %{inner_content: "", flash: %{}, socket_path: "/ws/live"}

      html =
        rendered_to_string(~H"""
        <Layouts.root inner_content={@inner_content} flash={@flash} socket_path={@socket_path} />
        """)

      assert html =~ ~s{<meta name="monitorex-socket-path" content="/ws/live"}
    end

    test "renders sidebar navigation links" do
      assigns = %{inner_content: "", flash: %{}}

      html =
        rendered_to_string(~H"""
        <Layouts.root inner_content={@inner_content} flash={@flash} />
        """)

      assert html =~ "Outbound"
      assert html =~ "Analysis"
      assert html =~ "Timeline"
      assert html =~ "Alerts"
      assert html =~ "Overview"
      assert html =~ "Consumers"
      assert html =~ "Recent"
      assert html =~ "Nodes"
    end

    test "renders flash messages when present" do
      assigns = %{inner_content: "", flash: %{"info" => "Welcome", "error" => nil}}

      html =
        rendered_to_string(~H"""
        <Layouts.root inner_content={@inner_content} flash={@flash} />
        """)

      assert html =~ "Welcome"
    end
  end

  describe "flash_group/1" do
    test "renders flash messages" do
      assigns = %{flash: %{"info" => "Hello", "error" => "Oops"}}

      html =
        rendered_to_string(~H"""
        <Layouts.flash_group flash={@flash} />
        """)

      assert html =~ "Hello"
      assert html =~ "Oops"
      assert html =~ "flash-info"
      assert html =~ "flash-error"
    end

    test "skips nil flash values" do
      assigns = %{flash: %{"info" => "Hello", "error" => nil}}

      html =
        rendered_to_string(~H"""
        <Layouts.flash_group flash={@flash} />
        """)

      assert html =~ "Hello"
      refute html =~ "Oops"
    end

    test "renders empty for empty flash" do
      assigns = %{flash: %{}}

      html =
        rendered_to_string(~H"""
        <Layouts.flash_group flash={@flash} />
        """)

      refute html =~ "flash flash-"
    end
  end
end
