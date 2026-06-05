defmodule Monitorex.Exports do
  @moduledoc """
  Export utilities for Monitorex — generates CSV and JSON from page data.

  Used by the dashboard export buttons to download current view as a file.
  """

  @doc """
  Generates CSV string from a list of maps (rows) and column definitions.

  Columns define both order and which keys to include. Handles commas,
  quotes, and newlines in cell values.
  """
  @spec to_csv([map()], [atom()]) :: String.t()
  def to_csv(data, fields) when is_list(fields) do
    header = Enum.map_join(fields, ",", &format_csv_cell/1) <> "\n"

    rows =
      Enum.map_join(data, "\n", fn row ->
        Enum.map_join(fields, ",", fn field ->
          format_csv_cell(Map.get(row, field, ""))
        end)
      end)

    header <> rows
  end

  @doc """
  Generates pretty-printed JSON from a list of maps or structs.

  When `fields` is provided, only those keys are included (same as CSV export).
  Structs are converted to plain maps before encoding.
  """
  @spec to_json([map()], [atom()]) :: String.t()
  def to_json(data, fields \\ []) do
    rows =
      if fields == [] do
        Enum.map(data, &struct_to_map/1)
      else
        Enum.map(data, fn row ->
          Map.new(fields, fn field -> {field, Map.get(row, field)} end)
        end)
      end

    Jason.encode!(rows, pretty: true)
  end

  defp struct_to_map(%{__struct__: _} = struct), do: Map.from_struct(struct)
  defp struct_to_map(map), do: map

  @doc """
  Sanitizes a filename for safe filesystem use.
  Replaces non-alphanumeric characters (except . - _) with underscores.
  """
  @spec sanitize_filename(String.t()) :: String.t()
  def sanitize_filename(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9._-]/, "_")
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
  end

  @doc """
  Builds a filename for an exported page.
  Format: monitorex_{page}_{timestamp}.{ext}
  """
  @spec filename(String.t(), String.t()) :: String.t()
  def filename(page_name, ext) do
    now =
      DateTime.utc_now()
      |> DateTime.to_string()
      |> String.slice(0, 19)
      |> String.replace(":", "-")

    "monitorex_#{sanitize_filename(page_name)}_#{now}.#{ext}"
  end

  defp format_csv_cell(value) when is_nil(value), do: ""
  defp format_csv_cell(value) when is_number(value), do: to_string(value)
  defp format_csv_cell(value) when is_atom(value), do: Atom.to_string(value)

  defp format_csv_cell(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end

  defp format_csv_cell(value), do: inspect(value)
end
