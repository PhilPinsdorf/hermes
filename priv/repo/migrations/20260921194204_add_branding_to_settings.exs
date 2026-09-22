defmodule Hermes.Repo.Migrations.AddBrandingToSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      # What this installation is called in the header, the browser tab and on
      # the login page.
      add :brand_name, :string, null: false, default: "Hermes"
      add :accent, :string, null: false, default: "slate"
      # The logo lives in the database, so a backup of the database restores
      # the whole appearance with it.
      add :logo_data, :binary
      add :logo_content_type, :string
      add :logo_updated_at, :utc_datetime
    end
  end
end
