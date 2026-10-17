defmodule BugTown.Faults.Fault do
  use Ecto.Schema
  import Ecto.Changeset

  schema "faults" do
    field :fault_type, :string
    field :status, :string, default: "active"
    field :severity, :string, default: "high"
    field :parameters, :map, default: %{}
    field :injected_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :resolved_at, :utc_datetime

    belongs_to :target_service, BugTown.Topology.Service
    belongs_to :target_dependency, BugTown.Topology.ServiceDependency
    has_many :bugs, BugTown.Bugs.BugEntity, foreign_key: :originating_fault_id
    has_many :incidents, BugTown.Incidents.Incident, foreign_key: :related_fault_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(fault, attrs) do
    fault
    |> cast(attrs, [
      :fault_type,
      :target_service_id,
      :target_dependency_id,
      :status,
      :severity,
      :parameters,
      :injected_at,
      :expires_at,
      :resolved_at
    ])
    |> validate_required([:fault_type, :injected_at])
  end
end
