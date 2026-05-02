defmodule Monitorex.Collector do
  @moduledoc """
  Collector GenServer responsible for monitoring HTTP endpoints.
  """

  use GenServer

  @doc false
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_args) do
    {:ok, %{}}
  end
end
