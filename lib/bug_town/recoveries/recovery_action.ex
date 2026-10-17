defmodule BugTown.Recoveries.RecoveryAction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "recovery_actions" do
    field :action_type, :string
    field :status, :string, default: "applied"
    field :parameters, :map, default: %{}
    field :metrics_before, :map, default: %{}
    field :metrics_after, :map, default: %{}
    field :time_to_recovery_ms, :integer
    field :success, :boolean, default: false
    field :applied_at, :utc_datetime
    field :verified_at, :utc_datetime

    belongs_to :target_service, BugTown.Topology.Service

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(recovery, attrs) do
    recovery
    |> cast(attrs, [
      :action_type,
      :target_service_id,
      :status,
      :parameters,
      :metrics_before,
      :metrics_after,
      :time_to_recovery_ms,
      :success,
      :applied_at,
      :verified_at
    ])
    |> validate_required([:action_type, :applied_at])
  end
end
