defmodule Hermes.Repo.Migrations.RemoveAccentFromSettings do
  use Ecto.Migration

  @doc """
  The accent colour was selectable per installation. It is now fixed in
  `assets/css/app.css`, so the column goes away. Rolling back brings it back
  with its old default.
  """
  def up do
    alter table(:settings) do
      remove :accent
    end
  end

  def down do
    alter table(:settings) do
      add :accent, :string, null: false, default: "slate"
    end
  end
end
