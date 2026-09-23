defmodule Hermes.Calls.CallLog do
  @moduledoc """
  One finished call.

  `result` says how it ended:

    * `:bridged` — put through to a person
    * `:announced` — nobody could take it; the caller heard the announcement
    * `:paused` — forwarding was switched off
    * `:all_busy` — everybody on duty was already in a call
    * `:rejected` — somebody pressed 3 (rejected for everyone)
    * `:blocked` — the caller's number is on the blocklist
    * `:abandoned` — the caller hung up before anything came of it
    * `:failed` — Asterisk refused something along the way
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Hermes.Calls.CallAttempt
  alias Hermes.Directory.Person

  @results [
    :bridged,
    :announced,
    :all_busy,
    :rejected,
    :paused,
    :blocked,
    :abandoned,
    :failed
  ]

  schema "call_logs" do
    field :channel_id, :string
    field :caller_number, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :total_seconds, :integer
    field :talk_seconds, :integer
    field :result, Ecto.Enum, values: @results
    belongs_to :person, Person
    has_many :attempts, CallAttempt, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  def results, do: @results

  @doc false
  def changeset(call_log, attrs) do
    call_log
    |> cast(attrs, [
      :channel_id,
      :caller_number,
      :started_at,
      :ended_at,
      :total_seconds,
      :talk_seconds,
      :result,
      :person_id
    ])
    |> validate_required([:channel_id, :started_at, :result])
    |> cast_assoc(:attempts, with: &CallAttempt.changeset/2)
    |> unique_constraint(:channel_id)
    |> foreign_key_constraint(:person_id)
  end
end
