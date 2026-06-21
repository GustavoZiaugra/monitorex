defmodule Monitorex.Notifiers.EmailTest do
  use ExUnit.Case, async: false

  alias Monitorex.Notifiers.Email

  @alert %{
    alert_name: "High error rate",
    host: "api.example.com",
    metric: :error_rate,
    value: 0.25,
    threshold: 0.05,
    operator: :gt,
    reason: "error rate too high",
    timestamp: 1_700_000_000
  }

  setup do
    on_exit(fn -> :meck.unload() end)
    :ok
  end

  test "returns :ok on successful send" do
    :meck.new(:gen_smtp_client, [:unstick])
    :meck.expect(:gen_smtp_client, :send_blocking, fn _email, _opts -> {:ok, "receipt"} end)

    assert Email.notify(@alert, %{to: "oncall@example.com"}) == :ok
  end

  test "supports string recipient" do
    :meck.new(:gen_smtp_client, [:unstick])
    :meck.expect(:gen_smtp_client, :send_blocking, fn _email, _opts -> {:ok, "receipt"} end)

    assert Email.notify(@alert, "oncall@example.com") == :ok
  end

  test "returns smtp_permanent_failure on permanent failure" do
    :meck.new(:gen_smtp_client, [:unstick])

    :meck.expect(:gen_smtp_client, :send_blocking, fn _email, _opts ->
      {:error, :no_more_hosts, {:mx, :permanent_failure, "bad"}}
    end)

    assert Email.notify(@alert, %{to: "oncall@example.com"}) == {:error, :smtp_permanent_failure}
  end

  test "returns error on other smtp failure" do
    :meck.new(:gen_smtp_client, [:unstick])
    :meck.expect(:gen_smtp_client, :send_blocking, fn _email, _opts -> {:error, :timeout} end)

    assert Email.notify(@alert, %{to: "oncall@example.com"}) == {:error, :timeout}
  end
end
