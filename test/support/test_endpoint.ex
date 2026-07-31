defmodule Monitorex.TestEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :monitorex

  socket("/live", Phoenix.LiveView.Socket)

  plug(Monitorex.TestRouter)
end
