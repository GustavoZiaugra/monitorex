defmodule Monitorex.Notifiers.SlackTest do
  use ExUnit.Case, async: false

  alias Monitorex.Notifiers.Slack

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

  test "returns :ok on 200 response" do
    :meck.new(:hackney, [:unstick])
    :meck.expect(:hackney, :post, fn _url, _headers, _body, _opts -> {:ok, 200, [], "ok"} end)

    assert Slack.notify(@alert, "https://hooks.slack.com/test") == :ok
    assert :meck.called(:hackney, :post, [:_, :_, :_, :_])
  end

  test "returns error on non-2xx response" do
    :meck.new(:hackney, [:unstick])
    :meck.expect(:hackney, :post, fn _url, _headers, _body, _opts -> {:ok, 400, [], "bad"} end)

    assert Slack.notify(@alert, "https://hooks.slack.com/test") == {:error, {:http_error, 400}}
  end

  test "returns error on hackney failure" do
    :meck.new(:hackney, [:unstick])
    :meck.expect(:hackney, :post, fn _url, _headers, _body, _opts -> {:error, :timeout} end)

    assert Slack.notify(@alert, "https://hooks.slack.com/test") == {:error, :timeout}
  end
end
