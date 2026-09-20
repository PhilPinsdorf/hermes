defmodule Hermes.Schedule.Shift do
  @moduledoc """
  A recurring weekly shift of one person, in local wall-clock time.

  `ends_at <= starts_at` means the shift runs past midnight into the next day
  (22:00 → 06:00). `ends_at == starts_at` is a full 24 hours.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Hermes.Directory.Person

  schema "shifts" do
    belongs_to :person, Person
    field :day_of_week, :integer
    field :starts_at, :time
    field :ends_at, :time
    # Order within the on-duty list: lower is called first.
    field :position, :integer, default: 0
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(shift, attrs) do
    shift
    |> cast(attrs, [:person_id, :day_of_week, :starts_at, :ends_at, :position, :active])
    |> validate_required([:person_id, :day_of_week, :starts_at, :ends_at])
    |> validate_inclusion(:day_of_week, 1..7)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> update_change(:starts_at, &truncate/1)
    |> update_change(:ends_at, &truncate/1)
    |> assoc_constraint(:person)
    |> check_constraint(:day_of_week, name: :day_of_week_range)
  end

  defp truncate(%Time{} = t), do: %{t | second: 0, microsecond: {0, 0}}

  @doc """
  True when the shift runs past midnight into the next day.
  """
  def overnight?(%__MODULE__{starts_at: s, ends_at: e}), do: Time.compare(e, s) != :gt

  @doc """
  Duration in minutes (1..1440).
  """
  def duration_minutes(%__MODULE__{starts_at: s, ends_at: e} = shift) do
    diff = div(Time.diff(e, s), 60)
    if overnight?(shift), do: diff + 1440, else: diff
  end
end
