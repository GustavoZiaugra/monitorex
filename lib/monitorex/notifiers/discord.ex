defmodule Monitorex.Notifiers.Discord do
  @moduledoc """
  Discord webhook notifier.

  Posts a JSON payload with an embed to the configured Discord webhook URL.
  """

  @behaviour Monitorex.Notifier

  require Logger

  @impl true
  def notify(alert, url) when is_binary(url) do
    payload = %{
      embeds: [
        %{
          title: "🚨 #{alert.alert_name}",
          color: 15_158_915,
          fields: [
            %{name: "Host", value: alert.host, inline: true},
            %{name: "Metric", value: to_string(alert.metric), inline: true},
            %{name: "Value", value: format_value(alert.value), inline: true},
            %{name: "Threshold", value: format_value(alert.threshold), inline: true},
            %{name: "Reason", value: alert.reason, inline: false}
          ],
          timestamp: DateTime.to_iso8601(DateTime.from_unix!(alert.timestamp)),
          footer: %{text: "Monitorex"}
        }
      ]
    }

    headers = [{"content-type", "application/json"}]
    body = Jason.encode!(payload)

    case :hackney.post(url, headers, body, [:with_body, timeout: 10_000, recv_timeout: 10_000]) do
      {:ok, status, _headers, _body} when status in 200..299 ->
        :ok

      {:ok, status, _headers, resp_body} ->
        Logger.warning("Discord notifier returned #{status}: #{resp_body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("Discord notifier failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp format_value(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 4)
  defp format_value(v), do: to_string(v)
end
