defmodule Monitorex.Collector do
  @moduledoc """
  GenServer responsible for collecting HTTP monitoring data.
  """

  use GenServer

  @doc false
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    {:ok, %{}}
  end
end
