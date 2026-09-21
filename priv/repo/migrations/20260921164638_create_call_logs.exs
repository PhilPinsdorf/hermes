defmodule Hermes.Repo.Migrations.CreateCallLogs do
  use Ecto.Migration

  def change do
    create table(:call_logs) do
      add :channel_id, :string, null: false
      # Caller number; emptied later by the retention job (personal data).
      add :caller_number, :string
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      # Total length of the call and, of that, the part actually talked.
      add :total_seconds, :integer
      add :talk_seconds, :integer
      add :result, :string, null: false
      # Who took the call, if anybody did.
      add :person_id, references(:people, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:call_logs, [:started_at])
    create index(:call_logs, [:result])
    create index(:call_logs, [:person_id])
    create unique_index(:call_logs, [:channel_id])

    create table(:call_attempts) do
      add :call_log_id, references(:call_logs, on_delete: :delete_all), null: false
      add :person_id, references(:people, on_delete: :nilify_all)
      # Kept so the log stays readable after a person has been deleted.
      add :person_name, :string, null: false
      add :position, :integer, null: false
      add :outcome, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:call_attempts, [:call_log_id])
    create index(:call_attempts, [:person_id])
  end
end
