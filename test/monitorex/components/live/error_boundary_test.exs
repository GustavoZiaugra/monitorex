defmodule Monitorex.Components.Live.ErrorBoundaryTest do
  use ExUnit.Case, async: true

  alias Monitorex.Components.Live.ErrorBoundary

  defp socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns),
      private: %{},
      redirected: nil
    }
  end

  test "update assigns component id and clears error" do
    {:ok, socket} = ErrorBoundary.update(%{id: "test-id"}, socket())

    assert socket.assigns.error == nil
    assert socket.assigns.component_id == "test-id"
  end

  test "retry event clears error" do
    socket = socket(%{error: "boom"})
    {:noreply, updated_socket} = ErrorBoundary.handle_event("retry", %{}, socket)

    assert updated_socket.assigns.error == nil
  end

  test "render function returns rendered struct" do
    rendered = ErrorBoundary.render(%{__changed__: %{}, error: nil, component_id: "x", myself: nil, inner_block: []})
    assert is_struct(rendered, Phoenix.LiveView.Rendered)
  end

  test "render function returns rendered struct with error" do
    rendered = ErrorBoundary.render(%{__changed__: %{}, error: "boom", component_id: "x", myself: nil, inner_block: []})
    assert is_struct(rendered, Phoenix.LiveView.Rendered)
  end

end
