defmodule Monitorex.Notifier do
  @moduledoc """
  Behaviour for alert notification channels.

  Implementations receive a structured alert map and dispatch it to
  external services (Slack, Discord, email, PagerDuty, etc.).
  """

  @type alert :: %{
          alert_name: String.t(),
          host: String.t(),
          value: number(),
          threshold: number(),
          operator: atom(),
          reason: String.t(),
          timestamp: integer(),
          metric: atom()
        }

  @callback notify(alert(), config :: term()) :: :ok | {:error, term()}
end
