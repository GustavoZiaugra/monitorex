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
    try do
      ts
      |> DateTime.from_unix(:microsecond)
      |> case do
        {:ok, dt} -> Calendar.strftime(dt, "%H:%M:%S")
        _ -> "-#{ts}-"
      end
    rescue
      _ -> "#{trunc(ts / 1_000_000)}s ago"
    end
  end
  def format_timestamp(_), do: "-"
end
