defmodule BugTown.Topology.ServiceDependency do
  use Ecto.Schema
  import Ecto.Changeset

  schema "service_dependencies" do
    field :protocol, :string, default: "http"
    field :latency_ms, :integer, default: 5
    field :critical, :boolean, default: true

    belongs_to :source_service, BugTown.Topology.Service
    belongs_to :target_service, BugTown.Topology.Service

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(dependency, attrs) do
    dependency
    |> cast(attrs, [:source_service_id, :target_service_id, :protocol, :latency_ms, :critical])
    |> validate_required([:source_service_id, :target_service_id])
    |> unique_constraint([:source_service_id, :target_service_id])
  end
end
