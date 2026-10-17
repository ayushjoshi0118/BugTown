defmodule BugTown.Repo do
  use Ecto.Repo,
    otp_app: :bug_town,
    adapter: Ecto.Adapters.Postgres
end
