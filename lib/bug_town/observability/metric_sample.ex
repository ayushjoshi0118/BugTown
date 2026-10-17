defmodule BugTown.Observability.MetricSample do
  use Ecto.Schema
  import Ecto.Changeset

  schema "metric_samples" do
    field :service_slug, :string
    field :rps, :float, default: 0.0
    field :avg_latency_ms, :float, default: 0.0
    field :p95_latency_ms, :float, default: 0.0
    field :error_rate, :float, default: 0.0
    field :cpu_pct, :float, default: 0.0
    field :memory_mb, :float, default: 0.0
    field :queue_depth, :integer, default: 0
    field :cache_hit_rate, :float, default: 0.0
    field :db_latency_ms, :float, default: 0.0
    field :availability_pct, :float, default: 100.0
    field :recorded_at, :utc_datetime
  end

  @doc false
  def changeset(sample, attrs) do
    sample
    |> cast(attrs, [
      :service_slug,
      :rps,
      :avg_latency_ms,
      :p95_latency_ms,
      :error_rate,
      :cpu_pct,
      :memory_mb,
      :queue_depth,
      :cache_hit_rate,
      :db_latency_ms,
      :availability_pct,
      :recorded_at
    ])
    |> validate_required([:service_slug, :recorded_at])
  end
end
