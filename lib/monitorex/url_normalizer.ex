defmodule Monitorex.UrlNormalizer do
  @moduledoc """
  Normalizes URLs to prevent high-cardinality URL explosion in the outbound dashboard.

  Dynamic path segments like UUIDs, numeric IDs, hex strings, and long tokens are
  replaced with generic placeholders (`:uuid`, `:id`, `:hex_id`, `:token`) so that
  similar endpoints are grouped together in the dashboard rather than creating an
  unbounded number of distinct entries.

  Supports:
  - Heuristic normalization of common dynamic segment patterns
  - User-defined regex → template patterns via application config
  - Cardinality cap per host (`:max_endpoints_per_host`, default 200)
  - Idempotent normalization (applying it twice produces the same result)
  """

  @uuid_pattern ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @numeric_pattern ~r/\A\d+\z/
  @hex_pattern ~r/\A[0-9a-fA-F]{8,}\z/
  @token_pattern ~r/\A[a-zA-Z0-9_\-\.]{8,}\z/

  @default_max_endpoints 200

  @doc """
  Normalizes a URL by replacing dynamic path segments with placeholders.

  Returns `nil` when given `nil`, empty string when given empty string.

  ## Examples

      iex> Monitorex.UrlNormalizer.normalize("https://api.example.com/users/12345")
      "https://api.example.com/users/:id"

      iex> Monitorex.UrlNormalizer.normalize("https://api.example.com/orders/550e8400-e29b-41d4-a716-446655440000")
      "https://api.example.com/orders/:uuid"

      iex> Monitorex.UrlNormalizer.normalize("https://api.example.com/v2/abc123def456")
      "https://api.example.com/v2/:hex_id"

      iex> Monitorex.UrlNormalizer.normalize("https://api.example.com/assets/a1b2c3d4e5f6_token_value")
      "https://api.example.com/assets/:token"

      iex> Monitorex.UrlNormalizer.normalize("https://api.example.com/users/123/orders/550e8400-e29b-41d4-a716-446655440000")
      "https://api.example.com/users/:id/orders/:uuid"

      iex> Monitorex.UrlNormalizer.normalize(nil)
      nil

      iex> Monitorex.UrlNormalizer.normalize("")
      ""

  """
  @spec normalize(url :: String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil
  def normalize(""), do: ""

  def normalize(url) when is_binary(url) do
    uri = URI.parse(url)
    path = uri.path || "/"

    segments = String.split(path, "/", trim: true)
    custom_patterns = Application.get_env(:monitorex, :url_normalizer_patterns, [])
    normalized = segments |> Enum.map(&normalize_segment(&1, custom_patterns))

    %{uri | path: "/" <> Enum.join(normalized, "/")} |> URI.to_string()
  end

  @doc """
  Normalizes a URL and applies the cardinality cap per host.

  `tracked_paths` is a MapSet of `{host, normalized_path}` tuples. If the host
  already has `max_endpoints_per_host` distinct normalized paths tracked, the
  result is bucketed to `/:other`.

  ## Examples

      iex> tracked = MapSet.new([{"api.example.com", "/users/:id"}])
      iex> Monitorex.UrlNormalizer.normalize("https://api.example.com/users/999", tracked)
      "https://api.example.com/users/:id"

  """
  @spec normalize(url :: String.t(), tracked_paths :: MapSet.t()) :: String.t()
  def normalize(url, tracked_paths) do
    normalized = normalize(url)
    uri = URI.parse(url)

    cardinality_limit =
      Application.get_env(:monitorex, :max_endpoints_per_host, @default_max_endpoints)

    host = uri.host
    path = uri.path

    if host && path && cardinality_limit > 0 do
      distinct =
        tracked_paths
        |> Enum.filter(fn {h, _p} -> h == host end)
        |> Enum.map(fn {_h, p} -> p end)
        |> MapSet.new()

      if MapSet.size(distinct) >= cardinality_limit and not MapSet.member?(distinct, normalized) do
        %{uri | path: "/:other"} |> URI.to_string()
      else
        normalized
      end
    else
      normalized
    end
  end

  @doc false
  @spec normalize_segment(segment :: String.t(), custom_patterns :: keyword()) :: String.t()
  def normalize_segment(segment, custom_patterns \\ []) do
    # Custom patterns take highest priority
    result =
      Enum.find_value(custom_patterns, fn {pattern, replacement} ->
        if Regex.match?(pattern, segment), do: replacement
      end)

    result ||
      cond do
        String.match?(segment, @uuid_pattern) -> ":uuid"
        String.match?(segment, @numeric_pattern) -> ":id"
        String.match?(segment, @hex_pattern) -> ":hex_id"
        String.match?(segment, @token_pattern) -> ":token"
        true -> segment
      end
  end
end
