defmodule BugTown.Observability.LogEntry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "log_entries" do
    field :timestamp, :utc_datetime
    field :severity, :string
    field :service_name, :string
    field :event_type, :string
    field :correlation_id, :string
    field :message, :string
    field :details, :map, default: %{}
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :timestamp,
      :severity,
      :service_name,
      :event_type,
      :correlation_id,
      :message,
      :details
    ])
    |> validate_required([:timestamp, :severity, :service_name, :event_type, :message])
  end
end
