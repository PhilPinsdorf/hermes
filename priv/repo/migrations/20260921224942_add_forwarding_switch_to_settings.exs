defmodule Hermes.Repo.Migrations.AddForwardingSwitchToSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      # The global switch: off means callers hear the announcement instead of
      # somebody's phone ringing (holidays, closing days, a quiet weekend).
      add :forwarding_enabled, :boolean, null: false, default: true
      add :forwarding_paused_at, :utc_datetime
    end
  end
end
