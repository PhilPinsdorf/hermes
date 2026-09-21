defmodule Hermes.Calls.CallAttempt do
  @moduledoc """
  One attempt to reach a person within a call. The outcomes are what makes
  patterns visible — e.g. a person whose voicemail keeps picking up
  (`:no_confirmation`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Hermes.Calls.CallLog
  alias Hermes.Directory.Person

  @outcomes [
    # pressed 1
    :confirmed,
    # pressed 2
    :passed,
    # pressed 3
    :rejected_all,
    # picked up but no key (voicemail, or nobody at the phone)
    :no_confirmation,
    :busy,
    :no_answer,
    # rejected on the phone itself
    :rejected,
    :failed
  ]

  schema "call_attempts" do
    belongs_to :call_log, CallLog
    belongs_to :person, Person
    field :person_name, :string
    field :position, :integer
    field :outcome, Ecto.Enum, values: @outcomes

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def outcomes, do: @outcomes

  @doc false
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:person_id, :person_name, :position, :outcome])
    |> validate_required([:person_name, :position, :outcome])
    |> foreign_key_constraint(:person_id)
  end
end
