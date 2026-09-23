defmodule Hermes.Blocklist.BlockedNumber do
  @moduledoc """
  A number whose calls Hermes answers with an announcement instead of ringing
  anybody.

  The number is stored in E.164, so the same caller blocked from the call log
  and typed in by hand end up as one entry.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Hermes.Directory.PhoneNumber

  schema "blocked_numbers" do
    field :number, :string
    field :note, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(blocked_number, attrs) do
    blocked_number
    |> cast(attrs, [:number, :note])
    |> update_change(:note, &String.trim/1)
    |> validate_required([:number])
    |> validate_length(:note, max: 200)
    |> PhoneNumber.validate_change(:number)
    |> unique_constraint(:number, message: "ist bereits blockiert")
  end
end
