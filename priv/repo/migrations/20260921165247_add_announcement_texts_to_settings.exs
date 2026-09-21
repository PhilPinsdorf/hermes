defmodule Hermes.Repo.Migrations.AddAnnouncementTextsToSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      # Announcement texts; audio is generated from them (Piper) when they change.
      add :text_no_one_on_duty, :text
      add :text_all_busy, :text
      add :text_confirm, :text
      # Mention the next shift start in the "nobody on duty" announcement.
      add :announce_next_shift, :boolean, null: false, default: true
    end
  end
end
