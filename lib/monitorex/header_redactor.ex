defmodule Monitorex.HeaderRedactor do
  @moduledoc """
  Redacts sensitive HTTP header values before events are stored.

  Header names matching the configured denylist (case-insensitive) have
  their values replaced with `"••••redacted••••"`.
  """

  @default_redacted ~w(authorization cookie set-cookie x-api-key x-auth-token)

  @doc """
  Returns the default list of sensitive header names.
  """
  @spec default_redacted_headers() :: [String.t()]
  def default_redacted_headers, do: @default_redacted

  @doc """
  Redacts header values whose names match the configured denylist.

  Accepts a list of `{name, value}` tuples where `name` may be a string
  or atom. Returns the same shape with matching values replaced.

  The denylist is read from application config `:redacted_headers`
  (defaults to `default_redacted_headers/0`).

  ## Examples

      iex> Monitorex.HeaderRedactor.redact_headers(
      ...>   [{"authorization", "Bearer secret"}, {"content-type", "application/json"}],
      ...>   ["authorization"]
      ...> )
      [{"authorization", "••••redacted••••"}, {"content-type", "application/json"}]

      iex> Monitorex.HeaderRedactor.redact_headers([], ["authorization"])
      []

  """
  @spec redact_headers([{atom() | String.t(), String.t()}], [String.t()]) :: [
          {atom() | String.t(), String.t()}
        ]
  def redact_headers(headers, redacted_list) do
    redacted_set =
      redacted_list
      |> Enum.map(&String.downcase/1)
      |> MapSet.new()

    Enum.map(headers, fn {name, value} ->
      if MapSet.member?(redacted_set, normalize_name(name)) do
        {name, "••••redacted••••"}
      else
        {name, value}
      end
    end)
  end

  @doc """
  Redacts headers using the application-configured denylist.
  """
  @spec redact_headers([{atom() | String.t(), String.t()}]) :: [
          {atom() | String.t(), String.t()}
        ]
  def redact_headers(headers) do
    redacted_list =
      Application.get_env(
        :monitorex,
        :redacted_headers,
        default_redacted_headers()
      )

    redact_headers(headers, redacted_list)
  end

  defp normalize_name(name) when is_atom(name), do: name |> Atom.to_string() |> String.downcase()
  defp normalize_name(name) when is_binary(name), do: String.downcase(name)
end
