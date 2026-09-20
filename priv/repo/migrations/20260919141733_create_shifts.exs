defmodule Hermes.Repo.Migrations.CreateShifts do
  use Ecto.Migration

  def change do
    create table(:shifts) do
      add :person_id, references(:people, on_delete: :delete_all), null: false
      # ISO weekday, 1 = Monday ... 7 = Sunday
      add :day_of_week, :integer, null: false
      # Local wall-clock times. ends_at <= starts_at means the shift runs into the next day.
      add :starts_at, :time, null: false
      add :ends_at, :time, null: false
      add :position, :integer, null: false, default: 0
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:shifts, [:person_id])
    create index(:shifts, [:day_of_week])
    create constraint(:shifts, :day_of_week_range, check: "day_of_week BETWEEN 1 AND 7")
  end
end
