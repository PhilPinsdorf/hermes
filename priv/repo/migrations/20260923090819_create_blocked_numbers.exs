defmodule Hermes.Repo.Migrations.CreateBlockedNumbers do
  use Ecto.Migration

  def change do
    create table(:blocked_numbers) do
      # E.164, so a number blocked from the call log and one typed in by hand
      # are the same entry.
      add :number, :string, null: false
      add :note, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:blocked_numbers, [:number])

    alter table(:settings) do
      add :text_blocked, :string
    end
  end
end
