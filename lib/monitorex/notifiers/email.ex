defmodule Monitorex.Notifiers.Email do
  @moduledoc """
  SMTP email notifier.

  Sends a plain-text email alert via the configured SMTP relay.
  Requires `:gen_smtp` as a dependency.
  """

  @behaviour Monitorex.Notifier

  require Logger

  @dialyzer {:no_return, notify: 2}
  @dialyzer {:no_contracts, notify: 2}
  @dialyzer {:no_fail_call, notify: 2}

  @impl true
  def notify(alert, config) when is_map(config) or is_binary(config) do
    to = if is_binary(config), do: config, else: config[:to] || config["to"]
    smtp_relay = Application.get_env(:monitorex, :smtp_relay, "localhost")
    smtp_port = Application.get_env(:monitorex, :smtp_port, 587)
    smtp_username = Application.get_env(:monitorex, :smtp_username)
    smtp_password = Application.get_env(:monitorex, :smtp_password)
    from = Application.get_env(:monitorex, :alert_from_email, "monitorex@localhost")

    subject = "[Monitorex] #{alert.alert_name} on #{alert.host}"

    body = """
    Monitorex Alert Fired
    =====================

    Alert:    #{alert.alert_name}
    Host:     #{alert.host}
    Metric:   #{alert.metric}
    Value:    #{format_value(alert.value)}
    Threshold:#{format_value(alert.threshold)} (#{alert.operator})
    Reason:   #{alert.reason}
    Time:     #{DateTime.from_unix!(alert.timestamp) |> DateTime.to_string()}
    """

    email =
      {from, [to],
       {[
          {"Subject", subject},
          {"From", from},
          {"To", to},
          {"Content-Type", "text/plain; charset=utf-8"}
        ], body}}

    opts =
      if smtp_username && smtp_password do
        [
          relay: smtp_relay,
          port: smtp_port,
          username: smtp_username,
          password: smtp_password,
          tls: :always,
          auth: :always
        ]
      else
        [relay: smtp_relay, port: smtp_port]
      end

    case :gen_smtp_client.send_blocking(email, opts) do
      {:ok, _receipt} ->
        :ok

      {:error, :no_more_hosts, {_, :permanent_failure, _}} ->
        Logger.warning("Email notifier: permanent SMTP failure to #{to}")
        {:error, :smtp_permanent_failure}

      {:error, reason} ->
        Logger.warning("Email notifier failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp format_value(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 4)
  defp format_value(v), do: to_string(v)
end
