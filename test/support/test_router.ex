defmodule Monitorex.TestRouter do
  @moduledoc false
  use Phoenix.Router

  import Monitorex.Router

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  scope "/" do
    pipe_through(:browser)
    http_dashboard([])
  end
end
