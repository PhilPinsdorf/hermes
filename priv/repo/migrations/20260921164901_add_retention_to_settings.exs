defmodule Hermes.Repo.Migrations.AddRetentionToSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      # Phone numbers are personal data: keep the log only as long as needed.
      add :call_log_retention_days, :integer, null: false, default: 90
      # Optional: drop just the caller number earlier than that (null = never).
      add :call_log_anonymize_after_days, :integer
    end
  end
end
