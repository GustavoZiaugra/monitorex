defmodule Monitorex.Collector.Handlers do
  @moduledoc false

  # These functions are defined in a separate module so telemetry does not emit
  # the "local function" warning. See :telemetry.attach/4 docs for details.

  def tesla(event_name, measurements, metadata, config) do
    case Monitorex.EventHandler.handle_tesla_event(event_name, measurements, metadata, config) do
      nil -> :ok
      event -> Monitorex.Collector.handle_event(event)
    end
  end

  def finch(event_name, measurements, metadata, config) do
    case Monitorex.EventHandler.handle_finch_event(event_name, measurements, metadata, config) do
      nil -> :ok
      event -> Monitorex.Collector.handle_event(event)
    end
  end

  def req(event_name, measurements, metadata, config) do
    case Monitorex.EventHandler.handle_req_event(event_name, measurements, metadata, config) do
      nil -> :ok
      event -> Monitorex.Collector.handle_event(event)
    end
  end

  def phoenix(event_name, measurements, metadata, config) do
    case Monitorex.EventHandler.handle_phoenix_event(event_name, measurements, metadata, config) do
      nil -> :ok
      event -> Monitorex.Collector.handle_event(event)
    end
  end
end
