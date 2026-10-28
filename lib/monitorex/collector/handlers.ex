defmodule Monitorex.Collector.Handlers do
  @moduledoc false

  # These functions are defined in a separate module so telemetry does not emit
  # the "local function" warning. See :telemetry.attach/4 docs for details.

  alias Monitorex.Collector
  alias Monitorex.EventHandler

  def tesla(event_name, measurements, metadata, config) do
    case EventHandler.handle_tesla_event(event_name, measurements, metadata, config) do
      nil -> :ok
      event -> Collector.handle_event(event)
    end
  end

  def finch(event_name, measurements, metadata, config) do
    case EventHandler.handle_finch_event(event_name, measurements, metadata, config) do
      nil -> :ok
      event -> Collector.handle_event(event)
    end
  end

  def finch_start(event_name, measurements, metadata, config) do
    EventHandler.handle_finch_start_event(event_name, measurements, metadata, config)
  end

  def finch_recv(event_name, measurements, metadata, config) do
    case EventHandler.handle_finch_recv_event(event_name, measurements, metadata, config) do
      nil -> :ok
      event -> Collector.handle_event(event)
    end
  end

  def finch_phase(event_name, measurements, metadata, config) do
    EventHandler.handle_finch_phase_event(event_name, measurements, metadata, config)
  end

  def req(event_name, measurements, metadata, config) do
    case EventHandler.handle_req_event(event_name, measurements, metadata, config) do
      nil -> :ok
      event -> Collector.handle_event(event)
    end
  end

  def phoenix(event_name, measurements, metadata, config) do
    case EventHandler.handle_phoenix_event(event_name, measurements, metadata, config) do
      nil -> :ok
      event -> Collector.handle_event(event)
    end
  end
end
