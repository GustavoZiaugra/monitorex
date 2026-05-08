defmodule Monitorex.LayoutsTest do
  use ExUnit.Case, async: true
  import Phoenix.Component
  import Phoenix.LiveViewTest

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

    test "includes CSS and JS asset links" do
      assigns = %{inner_content: "", flash: %{}}

      html =
        rendered_to_string(~H"""
        <Layouts.root inner_content={@inner_content} flash={@flash} />
        """)

      assert html =~ "/dashboard-assets/app.css"
      assert html =~ "/dashboard-assets/app.js"
    end

    test "renders sidebar navigation links" do
      assigns = %{inner_content: "", flash: %{}}

      html =
        rendered_to_string(~H"""
        <Layouts.root inner_content={@inner_content} flash={@flash} />
        """)

      assert html =~ "Outbound"
      assert html =~ "Outbound Recent"
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
