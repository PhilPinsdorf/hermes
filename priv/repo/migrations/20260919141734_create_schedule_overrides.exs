defmodule Hermes.Repo.Migrations.CreateScheduleOverrides do
  use Ecto.Migration

  def change do
    create table(:schedule_overrides) do
      add :person_id, references(:people, on_delete: :delete_all), null: false
      # "add" = on duty in addition / as a stand-in, "block" = absent (holiday, sick)
      add :kind, :string, null: false
      # Local wall-clock interval [starts_at, ends_at).
      add :starts_at, :naive_datetime, null: false
      add :ends_at, :naive_datetime, null: false
      add :note, :string

      timestamps(type: :utc_datetime)
    end

    create index(:schedule_overrides, [:person_id])
    create index(:schedule_overrides, [:ends_at])
    create constraint(:schedule_overrides, :ends_after_start, check: "ends_at > starts_at")
  end
end
