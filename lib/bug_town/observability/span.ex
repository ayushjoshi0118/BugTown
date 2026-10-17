defmodule BugTown.Observability.Span do
  use Ecto.Schema
  import Ecto.Changeset

  schema "spans" do
    field :span_id, :string
    field :trace_id, :string
    field :parent_span_id, :string
    field :service_name, :string
    field :start_time, :utc_datetime
    field :duration_ms, :float
    field :status, :string, default: "ok"
    field :error_details, :string

    belongs_to :trace, BugTown.Observability.Trace,
      foreign_key: :trace_id,
      references: :trace_id,
      define_field: false
  end

  @doc false
  def changeset(span, attrs) do
    span
    |> cast(attrs, [
      :span_id,
      :trace_id,
      :parent_span_id,
      :service_name,
      :start_time,
      :duration_ms,
      :status,
      :error_details
    ])
    |> validate_required([:span_id, :trace_id, :service_name, :start_time, :duration_ms])
  end
end
