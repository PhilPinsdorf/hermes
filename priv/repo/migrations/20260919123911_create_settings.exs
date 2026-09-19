defmodule Hermes.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    create table(:settings) do
      add :clip_number, :string
      add :clip_display_name, :string, null: false
      add :ring_timeout_seconds, :integer, null: false
      add :ring_strategy, :string, null: false
      add :max_external_channels, :integer, null: false
      add :busy_policy, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # Singleton: there is exactly one settings row per deployment.
    create constraint(:settings, :singleton, check: "id = 1")
  end
end
