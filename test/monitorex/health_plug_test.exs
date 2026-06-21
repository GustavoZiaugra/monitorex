defmodule Monitorex.HealthPlugTest do
  use ExUnit.Case, async: false

  alias Monitorex.Health
  alias Monitorex.HealthPlug
  alias Plug.Test

  setup do
    on_exit(fn -> :meck.unload() end)
    :ok
  end

  test "returns JSON health status with CORS header" do
    conn =
      :get
      |> Test.conn("/monitorex/health")
      |> HealthPlug.call([])

    assert conn.status == 200
    assert {"content-type", "application/json; charset=utf-8"} in conn.resp_headers
    assert {"access-control-allow-origin", "*"} in conn.resp_headers

    body = Jason.decode!(conn.resp_body)
    assert body["status"] in ["healthy", "degraded", "unhealthy"]
  end

  test "returns 503 when unhealthy" do
    :meck.new(Health, [:unstick])
    :meck.expect(Health, :check, fn -> %{status: :unhealthy} end)

    conn =
      :get
      |> Test.conn("/monitorex/health")
      |> HealthPlug.call([])

    assert conn.status == 503
    assert Jason.decode!(conn.resp_body)["status"] == "unhealthy"
  end

  test "returns 200 when degraded" do
    :meck.new(Health, [:unstick])
    :meck.expect(Health, :check, fn -> %{status: :degraded} end)

    conn =
      :get
      |> Test.conn("/monitorex/health")
      |> HealthPlug.call([])

    assert conn.status == 200
  end
end
