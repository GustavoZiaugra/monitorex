defmodule Monitorex.Notifiers.Slack do
  @moduledoc """
  Slack incoming-webhook notifier.

  Posts a JSON payload to the configured Slack webhook URL.
  """

  @behaviour Monitorex.Notifier

  require Logger

  @impl true
  def notify(alert, url) when is_binary(url) do
    payload = %{
      text: "🚨 Monitorex Alert: #{alert.alert_name}",
      attachments: [
        %{
          color: "danger",
          fields: [
            %{title: "Host", value: alert.host, short: true},
            %{title: "Metric", value: to_string(alert.metric), short: true},
            %{title: "Value", value: format_value(alert.value), short: true},
            %{title: "Threshold", value: format_value(alert.threshold), short: true},
            %{title: "Reason", value: alert.reason, short: false}
          ],
          footer: "Monitorex",
          ts: alert.timestamp
        }
      ]
    }

    headers = [{"content-type", "application/json"}]
    body = Jason.encode!(payload)

    case :hackney.post(url, headers, body, [:with_body, timeout: 10_000, recv_timeout: 10_000]) do
      {:ok, status, _headers, _body} when status in 200..299 ->
        :ok

      {:ok, status, _headers, resp_body} ->
        Logger.warning("Slack notifier returned #{status}: #{resp_body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("Slack notifier failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp format_value(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 4)
  defp format_value(v), do: to_string(v)
end
