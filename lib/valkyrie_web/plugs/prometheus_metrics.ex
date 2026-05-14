defmodule ValkyrieWeb.Plugs.PrometheusMetrics do
  @moduledoc """
  Serves the Prometheus scrape endpoint by calling
  `TelemetryMetricsPrometheus.Core.scrape/1`.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: Keyword.get(opts, :name, :prometheus_metrics)

  @impl true
  def call(conn, name) do
    metrics = TelemetryMetricsPrometheus.Core.scrape(name)

    conn
    |> put_resp_content_type("text/plain; version=0.0.4", nil)
    |> send_resp(200, metrics)
    |> halt()
  end
end
