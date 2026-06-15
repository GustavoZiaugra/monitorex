defmodule Monitorex.Components.Live.Helpers do
  @moduledoc """
  Shared helper functions for LiveView components.
  """

  @doc """
  Formats a timestamp for display.

  Returns:
  - `"-"` for nil or unknown format
  - `"HH:MM:SS"` for valid Unix microsecond timestamps
  - `"Xs ago"` for timestamps that fail conversion (legacy format fallback)
  """
  def format_timestamp(nil), do: "-"

  def format_timestamp(ts) when is_integer(ts) do
    ts
    |> DateTime.from_unix(:microsecond)
    |> case do
      {:ok, dt} -> Calendar.strftime(dt, "%H:%M:%S")
      _ -> "-#{ts}-"
    end
  rescue
    _ -> "#{trunc(ts / 1_000_000)}s ago"
  end

  def format_timestamp(_), do: "-"

  @doc """
  Returns the CSS class for a status filter chip.

  When `value` matches `current`, returns an active variant. Otherwise returns
  the base class.
  """
  def status_chip_class(value, current) do
    base = "filter-chip"

    if value == current do
      case value do
        "2xx" -> "#{base} active-2xx"
        "3xx" -> "#{base} active-3xx"
        "4xx" -> "#{base} active-4xx"
        "5xx" -> "#{base} active-5xx"
        _ -> "#{base} active"
      end
    else
      base
    end
  end
end
