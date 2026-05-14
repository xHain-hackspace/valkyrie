defmodule ValkyrieWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      {TelemetryMetricsPrometheus.Core, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @http_buckets [10, 25, 50, 100, 250, 500, 1000, 2500, 5000]
  @db_buckets [1, 5, 10, 25, 50, 100, 250, 500, 1000]

  def metrics do
    [
      # Phoenix Metrics
      distribution("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: @http_buckets]
      ),
      distribution("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond},
        reporter_options: [buckets: @http_buckets]
      ),
      counter("phoenix.router_dispatch.exception.duration", tags: [:route]),
      distribution("phoenix.socket_connected.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: @http_buckets]
      ),
      sum("phoenix.socket_drain.count"),
      distribution("phoenix.channel_joined.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: @http_buckets]
      ),
      distribution("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond},
        reporter_options: [buckets: @http_buckets]
      ),

      # Database Metrics
      distribution("valkyrie.repo.query.total_time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: @db_buckets],
        description: "The sum of the other measurements"
      ),
      distribution("valkyrie.repo.query.query_time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: @db_buckets],
        description: "The time spent executing the query"
      ),
      distribution("valkyrie.repo.query.queue_time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: @db_buckets],
        description: "The time spent waiting for a database connection"
      ),

      # VM Metrics
      last_value("vm.memory.total", unit: {:byte, :kilobyte}),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io"),

      # Mailer Metrics
      counter(
        [:swoosh, :deliver, :total],
        event_name: [:swoosh, :deliver, :stop],
        measurement: :duration,
        tags: [:mailer, :status],
        tag_values: &__MODULE__.mailer_tags/1,
        description: "Number of email delivery attempts by status"
      ),
      distribution("swoosh.deliver.stop.duration",
        tags: [:mailer],
        tag_values: &__MODULE__.mailer_tags/1,
        unit: {:native, :millisecond},
        reporter_options: [buckets: [50, 100, 250, 500, 1000, 2500, 5000, 10_000]],
        description: "Email delivery duration"
      ),
      counter("swoosh.deliver.exception.duration",
        tags: [:mailer],
        tag_values: &__MODULE__.mailer_tags/1,
        description: "Email delivery crashes"
      ),

      # Member sync metrics
      counter(
        [:valkyrie, :members, :sync, :total],
        event_name: [:valkyrie, :members, :sync, :stop],
        measurement: :duration,
        tags: [:status],
        description: "Member sync runs by status (:ok or :error)"
      ),
      distribution("valkyrie.members.sync.stop.duration",
        unit: {:native, :millisecond},
        reporter_options: [
          buckets: [100, 500, 1000, 5000, 10_000, 30_000, 60_000, 120_000]
        ],
        description: "Member sync duration"
      ),
      counter("valkyrie.members.sync.exception.duration",
        description: "Member sync crashes"
      ),
      last_value("valkyrie.members.keyholders.count",
        description: "Current number of members marked as keyholders"
      ),
      last_value("valkyrie.members.total.count",
        description: "Current total number of members"
      )
    ]
  end

  def mailer_tags(metadata) do
    mailer =
      case metadata[:mailer] do
        nil -> "unknown"
        mod -> inspect(mod)
      end

    status =
      cond do
        Map.has_key?(metadata, :error) -> "error"
        Map.has_key?(metadata, :reason) -> "exception"
        true -> "ok"
      end

    %{mailer: mailer, status: status}
  end

  defp periodic_measurements do
    [
      {Valkyrie.Members.Stats, :emit_member_counts, []}
    ]
  end
end
