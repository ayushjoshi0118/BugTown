defmodule BugTown.Incidents.Incident do
  use Ecto.Schema
  import Ecto.Changeset

  schema "incidents" do
    field :incident_code, :string
    field :title, :string
    field :severity, :string, default: "high"
    field :status, :string, default: "open"
    field :root_cause, :string
    field :affected_service_names, {:array, :string}, default: []
    field :timeline_events, {:array, :map}, default: []
    field :notes, :string
    field :acknowledged_at, :utc_datetime
    field :resolved_at, :utc_datetime

    belongs_to :related_fault, BugTown.Faults.Fault

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(incident, attrs) do
    incident
    |> cast(attrs, [
      :incident_code,
      :title,
      :severity,
      :status,
      :root_cause,
      :affected_service_names,
      :related_fault_id,
      :timeline_events,
      :notes,
      :acknowledged_at,
      :resolved_at
    ])
    |> validate_required([:incident_code, :title])
    |> unique_constraint(:incident_code)
  end
end
