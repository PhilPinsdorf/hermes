defmodule Hermes.Repo.Migrations.CreatePeople do
  use Ecto.Migration

  def change do
    create table(:people) do
      add :name, :string, null: false
      add :phone_e164, :string, null: false
      add :active, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0
      add :notes, :text
      add :ring_timeout_seconds, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:people, [:phone_e164])
  end
end
