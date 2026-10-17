defmodule BugTown.Topology.Service do
  use Ecto.Schema
  import Ecto.Changeset

  schema "services" do
    field :name, :string
    field :slug, :string
    field :category, :string
    field :status, :string, default: "healthy"
    field :baseline_latency_ms, :integer, default: 20
    field :baseline_error_rate, :float, default: 0.001
    field :baseline_cpu, :float, default: 15.0
    field :baseline_memory_mb, :integer, default: 256
    field :pos_x, :integer, default: 100
    field :pos_y, :integer, default: 100
    field :metadata, :map, default: %{}

    has_many :outgoing_dependencies, BugTown.Topology.ServiceDependency,
      foreign_key: :source_service_id

    has_many :incoming_dependencies, BugTown.Topology.ServiceDependency,
      foreign_key: :target_service_id

    has_many :faults, BugTown.Faults.Fault, foreign_key: :target_service_id
    has_many :bugs, BugTown.Bugs.BugEntity, foreign_key: :current_service_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(service, attrs) do
    service
    |> cast(attrs, [
      :name,
      :slug,
      :category,
      :status,
      :baseline_latency_ms,
      :baseline_error_rate,
      :baseline_cpu,
      :baseline_memory_mb,
      :pos_x,
      :pos_y,
      :metadata
    ])
    |> validate_required([:name, :slug, :category])
    |> unique_constraint(:slug)
  end
end
