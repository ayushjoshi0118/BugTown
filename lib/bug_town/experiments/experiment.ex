defmodule BugTown.Experiments.Experiment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "experiments" do
    field :name, :string
    field :scenario_type, :string
    field :description, :string
    field :seed, :integer, default: 42
    field :status, :string, default: "completed"
    field :fault_config, :map, default: %{}
    field :recovery_config, :map, default: %{}
    field :metrics_summary, :map, default: %{}
    field :duration_seconds, :integer, default: 60
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(experiment, attrs) do
    experiment
    |> cast(attrs, [
      :name,
      :scenario_type,
      :description,
      :seed,
      :status,
      :fault_config,
      :recovery_config,
      :metrics_summary,
      :duration_seconds,
      :started_at,
      :completed_at
    ])
    |> validate_required([:name, :scenario_type])
  end
end
