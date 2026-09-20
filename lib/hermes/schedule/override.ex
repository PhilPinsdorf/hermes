defmodule Hermes.Schedule.Override do
  @moduledoc """
  A one-off exception to the weekly plan, in local wall-clock time:

    * `:add`   — the person is on duty in this interval (stand-in, extra duty)
    * `:block` — the person is not on duty in this interval, even if a shift
                 says so (holiday, sick leave)

  The interval is half-open: `[starts_at, ends_at)`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Hermes.Directory.Person

  @kinds [:add, :block]

  schema "schedule_overrides" do
    belongs_to :person, Person
    field :kind, Ecto.Enum, values: @kinds
    field :starts_at, :naive_datetime
    field :ends_at, :naive_datetime
    field :note, :string

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  @doc false
  def changeset(override, attrs) do
    override
    |> cast(attrs, [:person_id, :kind, :starts_at, :ends_at, :note])
    |> validate_required([:person_id, :kind, :starts_at, :ends_at])
    |> validate_length(:note, max: 200)
    |> validate_order()
    |> assoc_constraint(:person)
    |> check_constraint(:ends_at, name: :ends_after_start, message: "muss nach dem Beginn liegen")
  end

  defp validate_order(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && NaiveDateTime.compare(ends_at, starts_at) != :gt do
      add_error(changeset, :ends_at, "muss nach dem Beginn liegen")
    else
      changeset
    end
  end
end
