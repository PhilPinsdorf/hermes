defmodule Hermes.Directory.Person do
  @moduledoc """
  Someone who can be on duty and whose mobile phone calls are forwarded to.

  The phone number is private: it is only ever dialed by Asterisk and never
  shown to a caller.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Hermes.Directory.PhoneNumber

  schema "people" do
    field :name, :string
    field :phone_e164, :string
    field :active, :boolean, default: true
    field :position, :integer, default: 0
    field :notes, :string
    # Overrides the global ring timeout for this person when set.
    field :ring_timeout_seconds, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(person, attrs) do
    person
    |> cast(attrs, [:name, :phone_e164, :active, :position, :notes, :ring_timeout_seconds])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :phone_e164])
    |> validate_length(:name, max: 100)
    |> validate_length(:notes, max: 2000)
    # A desk phone or softphone on the same Fritz!Box may take calls too.
    |> PhoneNumber.validate_change(:phone_e164, allow_internal: true)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_number(:ring_timeout_seconds,
      greater_than_or_equal_to: 5,
      less_than_or_equal_to: 120
    )
    |> unique_constraint(:phone_e164, message: "ist bereits einer anderen Person zugeordnet")
  end
end
