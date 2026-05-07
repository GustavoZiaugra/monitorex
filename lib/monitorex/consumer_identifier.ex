defmodule Monitorex.ConsumerIdentifier do
  @moduledoc """
  Extracts a consumer label from an inbound `Plug.Conn` for per-consumer dashboard breakdowns.

  ## Priority order

  1. **Custom function** — `consumer_fn` in Application config (arity 1, receives `conn`)
  2. **Basic-auth username** — decoded from `authorization` header, password discarded
  3. **API key header** — value of `x-api-key` truncated to 8 characters
  4. **`nil`** — unknown / anonymous consumer
  """

  @doc """
  Identifies the consumer from a `Plug.Conn`.

  Returns `nil` when no consumer can be determined.
  """
  @spec identify(conn :: Plug.Conn.t()) :: String.t() | nil
  def identify(conn) do
    # 1. Custom function from config (highest priority)
    with nil <- custom_fn_result(conn) do
      # 2. Basic-auth username
      with nil <- extract_basic_auth_username(conn) do
        # 3. x-api-key header (first 8 chars)
        extract_api_key(conn)
      end
    end
    # 4. nil is the implicit fallback from all three returning nil
  end

  # ── Custom function ──

  defp custom_fn_result(conn) do
    case Application.get_env(:monitorex, :consumer_fn) do
      fun when is_function(fun, 1) -> fun.(conn)
      _ -> nil
    end
  end

  # ── Basic-Auth extraction ──

  defp extract_basic_auth_username(conn) do
    with auth_value when is_binary(auth_value) <- Plug.Conn.get_req_header(conn, "authorization") |> List.first(),
         "Basic " <> encoded <- auth_value,
         decoded when is_binary(decoded) <- base64_decode(encoded),
         [username | _] <- String.split(decoded, ":", parts: 2),
         username when username != "" <- username do
      username
    else
      _ -> nil
    end
  end

  defp base64_decode(encoded) do
    encoded = String.trim(encoded)

    try do
      case Base.decode64(encoded) do
        {:ok, decoded} -> decoded
        _ -> nil
      end
    rescue
      _ -> nil
    end
  end

  # ── API key extraction ──

  defp extract_api_key(conn) do
    case Plug.Conn.get_req_header(conn, "x-api-key") |> List.first() do
      nil -> nil
      key -> String.slice(key, 0, 8)
    end
  end
end
