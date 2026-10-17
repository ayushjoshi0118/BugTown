defmodule BugTown.Observability.Trace do
  use Ecto.Schema
  import Ecto.Changeset

  schema "traces" do
    field :trace_id, :string
    field :root_service, :string
    field :duration_ms, :float
    field :status, :string, default: "ok"
    field :timestamp, :utc_datetime

    has_many :spans, BugTown.Observability.Span, foreign_key: :trace_id, references: :trace_id
  end

  @doc false
  def changeset(trace, attrs) do
    trace
    |> cast(attrs, [:trace_id, :root_service, :duration_ms, :status, :timestamp])
    |> validate_required([:trace_id, :root_service, :duration_ms, :timestamp])
    |> unique_constraint(:trace_id)
  end
end
