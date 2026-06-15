defmodule Monitorex.ExportPlug do
  @moduledoc """
  Plug that serves CSV/JSON exports of Monitorex dashboard data.

  ## Route

      GET /export/:page/:format

  Returns a downloadable file with the appropriate Content-Type and
  Content-Disposition headers.

  ## Supported pages

  See `Monitorex.Exports` for page names and field definitions.
  """

  import Plug.Conn

  alias Monitorex.ClusterPage
  alias Monitorex.Exports
  alias Monitorex.Storage

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    page = conn.params["page"]
    format = conn.params["format"]

    data = fetch_data(page)

    case {data, format} do
      {_, fmt} when fmt not in ["csv", "json"] ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(400, "Invalid format. Use 'csv' or 'json'.\n")

      {[], _} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "No data available for export.\n")

      {data, "csv"} ->
        fields = export_fields_for(page)
        csv = Exports.to_csv(data, fields)
        filename = Exports.filename(page, "csv")

        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"#{filename}\""
        )
        |> send_resp(200, csv)

      {data, "json"} ->
        fields = export_fields_for(page)
        json = Exports.to_json(data, fields)
        filename = Exports.filename(page, "json")

        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"#{filename}\""
        )
        |> send_resp(200, json)
    end
  end

  defp fetch_data("outbound_overview") do
    ClusterPage.list_hosts()
  end

  defp fetch_data("outbound_recent") do
    ClusterPage.list_recent_outbound(limit: 500)
  end

  defp fetch_data("host_detail") do
    # Will be re-fetched per host if needed
    []
  end

  defp fetch_data("inbound_overview") do
    ClusterPage.list_routes()
  end

  defp fetch_data("inbound_consumers") do
    ClusterPage.list_consumers()
  end

  defp fetch_data("inbound_recent") do
    ClusterPage.list_recent_inbound(limit: 500)
  end

  defp fetch_data("timeline") do
    Storage.list_recent_outbound(limit: 500)
  end

  defp fetch_data("route_detail") do
    ClusterPage.list_consumers()
  end

  defp fetch_data(_), do: []

  defp export_fields_for("outbound_overview"),
    do: [:host, :client, :requests, :errors, :error_rate, :avg_latency, :p50, :p95, :p99]

  defp export_fields_for("outbound_recent"),
    do: [:method, :host, :path, :status, :duration_ms, :timestamp, :source]

  defp export_fields_for("host_detail"),
    do: [:path, :requests, :errors, :error_rate, :avg_latency, :last_seen]

  defp export_fields_for("inbound_overview"),
    do: [:method, :path, :requests, :errors, :error_rate, :avg_latency, :p50, :p95, :p99]

  defp export_fields_for("inbound_consumers"),
    do: [:consumer, :requests, :errors, :total_duration, :avg_latency, :last_seen]

  defp export_fields_for("inbound_recent"),
    do: [:method, :path, :status, :duration_ms, :timestamp, :consumer]

  defp export_fields_for("timeline"),
    do: [:source, :direction, :method, :host, :path, :status, :duration_ms, :timestamp]

  defp export_fields_for("route_detail"),
    do: [:consumer, :requests, :errors, :avg_latency, :last_seen]

  defp export_fields_for(_), do: []
end
