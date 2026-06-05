defmodule Monitorex.URLRedactor do
  @moduledoc """
  Redacts sensitive query parameters from URLs to prevent accidental leakage
  of tokens, keys, and credentials in stored/displayed outbound URLs.

  Sensitive param values are replaced with `[REDACTED]` before the URL is
  written to storage.
  """

  @default_sensitive ~w(key token api_key apikey secret password auth access_token refresh_token)

  @doc """
  Redacts sensitive query parameters from the given URL.

  Uses the application config key `:sensitive_query_params` to determine
  which parameters to redact (defaults to a built-in denylist).

  ## Examples

      iex> Monitorex.URLRedactor.redact("https://api.stripe.com/v1/charges?key=sk_live_xxx")
      "https://api.stripe.com/v1/charges?key=%5BREDACTED%5D"

      iex> Monitorex.URLRedactor.redact("https://api.example.com/users/123?page=1&per_page=20")
      "https://api.example.com/users/123?page=1&per_page=20"

      iex> Monitorex.URLRedactor.redact("https://api.example.com/health")
      "https://api.example.com/health"

      iex> Monitorex.URLRedactor.redact(nil)
      nil

      iex> Monitorex.URLRedactor.redact("")
      ""

  """
  @spec redact(url :: String.t() | nil) :: String.t() | nil
  def redact(nil), do: nil
  def redact(""), do: ""

  def redact(url) when is_binary(url) do
    uri = URI.parse(url)

    if is_nil(uri.query) or uri.query == "" do
      url
    else
      sensitive = Application.get_env(:monitorex, :sensitive_query_params, @default_sensitive)
      sensitive_set = MapSet.new(sensitive)

      params =
        uri.query
        |> URI.query_decoder()
        |> Enum.to_list()

      redacted =
        Enum.map(params, fn {key, value} ->
          if MapSet.member?(sensitive_set, key), do: {key, "[REDACTED]"}, else: {key, value}
        end)

      new_query = URI.encode_query(redacted)
      URI.to_string(%{uri | query: new_query})
    end
  end
end
