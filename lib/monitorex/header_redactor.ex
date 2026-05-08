defmodule Monitorex.HeaderRedactor do
  @moduledoc """
  Redacts sensitive HTTP header values before storage.

  Reads the configured `:redacted_headers` list (case-insensitive) and replaces
  matching header values with `"••••redacted••••"`.

  ## Configuration

      config :monitorex, :redacted_headers, ["authorization", "x-api-key", "cookie"]

  If unset, defaults to `["authorization", "cookie", "set-cookie", "x-api-key", "x-auth-token"]`.
  """

  @doc """
  Returns the default list of redacted header names.
  """
  def default_redacted_headers do
    ["authorization", "cookie", "set-cookie", "x-api-key", "x-auth-token"]
  end

  @doc """
  Redacts sensitive values from a list of `{name, value}` header tuples.

  Returns the same list with matching header values replaced by `"••••redacted••••"`.
  Non-matching headers are returned unchanged.

  ## Examples

      iex> Monitorex.HeaderRedactor.redact_headers([{"authorization", "Bearer secret123"}], ["authorization"])
      [{"authorization", "••••redacted••••"}]

      iex> Monitorex.HeaderRedactor.redact_headers([{"x-api-key", "abc123"}, {"host", "example.com"}], ["x-api-key"])
      [{"x-api-key", "••••redacted••••"}, {"host", "example.com"}]

      iex> Monitorex.HeaderRedactor.redact_headers(nil, ["authorization"])
      nil

      iex> Monitorex.HeaderRedactor.redact_headers([], ["authorization"])
      []
  """
  @spec redact_headers(list({String.t(), String.t()}) | nil, [String.t()]) :: list({String.t(), String.t()}) | nil
  def redact_headers(nil, _redacted_list), do: nil
  def redact_headers([], _redacted_list), do: []

  def redact_headers(headers, redacted_list) when is_list(headers) do
    redacted_set = MapSet.new(redacted_list, &String.downcase/1)

    Enum.map(headers, fn {name, value} ->
      if MapSet.member?(redacted_set, String.downcase(name)) do
        {name, "••••redacted••••"}
      else
        {name, value}
      end
    end)
  end
end
