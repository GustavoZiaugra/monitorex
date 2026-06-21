defmodule Monitorex.Notifiers.DiscordTest do
  use ExUnit.Case, async: false

  alias Monitorex.Notifiers.Discord

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

  test "returns :ok on 204 response" do
    :meck.new(:hackney, [:unstick])
    :meck.expect(:hackney, :post, fn _url, _headers, _body, _opts -> {:ok, 204, [], ""} end)

    assert Discord.notify(@alert, "https://discord.com/api/webhooks/test") == :ok
    assert :meck.called(:hackney, :post, [:_, :_, :_, :_])
  end

  test "returns error on non-2xx response" do
    :meck.new(:hackney, [:unstick])
    :meck.expect(:hackney, :post, fn _url, _headers, _body, _opts -> {:ok, 429, [], "rate limited"} end)

    assert Discord.notify(@alert, "https://discord.com/api/webhooks/test") == {:error, {:http_error, 429}}
  end

  test "returns error on hackney failure" do
    :meck.new(:hackney, [:unstick])
    :meck.expect(:hackney, :post, fn _url, _headers, _body, _opts -> {:error, :connect_timeout} end)

    assert Discord.notify(@alert, "https://discord.com/api/webhooks/test") == {:error, :connect_timeout}
  end
end
