defmodule BugTown.Bugs.BugEntity do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bug_entities" do
    field :entity_code, :string
    field :bug_type, :string
    field :severity, :string, default: "high"
    field :status, :string, default: "spawned"
    field :impact_score, :integer, default: 50
    field :movement_history, {:array, :map}, default: []
    field :spawned_at, :utc_datetime
    field :resolved_at, :utc_datetime

    belongs_to :current_service, BugTown.Topology.Service
    belongs_to :originating_fault, BugTown.Faults.Fault

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(bug, attrs) do
    bug
    |> cast(attrs, [
      :entity_code,
      :bug_type,
      :severity,
      :status,
      :impact_score,
      :movement_history,
      :current_service_id,
      :originating_fault_id,
      :spawned_at,
      :resolved_at
    ])
    |> validate_required([:entity_code, :bug_type, :spawned_at])
    |> unique_constraint(:entity_code)
  end
end
