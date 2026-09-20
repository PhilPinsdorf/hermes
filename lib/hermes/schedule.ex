defmodule Hermes.Schedule do
  @moduledoc """
  The Schedule context: the weekly plan (shifts), one-off exceptions
  (overrides) and resolving who is on duty.

  The resolution logic itself lives in the pure `Hermes.Schedule.Resolver`;
  this module loads the data and supplies the configured time zone.
  """

  import Ecto.Query, warn: false
  alias Hermes.Repo

  alias Hermes.Schedule.{Override, Resolver, Shift}

  @topic "schedule"

  @doc """
  The time zone shifts and overrides are interpreted in.
  """
  def time_zone, do: Application.get_env(:hermes, :time_zone, "Europe/Berlin")

  @doc """
  Subscribes the caller to `{:schedule_changed, _}` messages.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Hermes.PubSub, @topic)
  end

  ## Resolution

  @doc """
  Pure resolution with the configured time zone. See `Resolver.on_duty_at/4`.
  """
  def on_duty_at(%DateTime{} = at, shifts, overrides) do
    Resolver.on_duty_at(at, shifts, overrides, time_zone())
  end

  @doc """
  Loads the plan and returns who is on duty at `at` (default: now) and the
  next change:

      %{on_duty: [%Person{}], next_change: {%DateTime{}, [%Person{}]} | nil}
  """
  def status(at \\ DateTime.utc_now()) do
    shifts = list_shifts()
    overrides = list_overrides_relevant_at(at)

    %{
      on_duty: Resolver.on_duty_at(at, shifts, overrides, time_zone()),
      next_change: Resolver.next_change(at, shifts, overrides, time_zone())
    }
  end

  ## Shifts

  @doc """
  All shifts with their person, ordered by day and start time.
  """
  def list_shifts do
    Repo.all(
      from s in Shift,
        order_by: [asc: s.day_of_week, asc: s.starts_at, asc: s.position],
        preload: :person
    )
  end

  def get_shift!(id), do: Shift |> Repo.get!(id) |> Repo.preload(:person)

  def create_shift(attrs) do
    %Shift{}
    |> Shift.changeset(attrs)
    |> Repo.insert()
    |> broadcast()
  end

  def update_shift(%Shift{} = shift, attrs) do
    shift
    |> Shift.changeset(attrs)
    |> Repo.update()
    |> broadcast()
  end

  def delete_shift(%Shift{} = shift) do
    shift
    |> Repo.delete()
    |> broadcast()
  end

  def change_shift(%Shift{} = shift, attrs \\ %{}) do
    Shift.changeset(shift, attrs)
  end

  ## Overrides

  @doc """
  Overrides that have not ended yet at `at`, ordered by start.
  """
  def list_upcoming_overrides(at \\ DateTime.utc_now()) do
    now = local_naive(at)

    Repo.all(
      from o in Override,
        where: o.ends_at > ^now,
        order_by: [asc: o.starts_at],
        preload: :person
    )
  end

  # Overrides that can matter for `at` and the resolver's look-ahead.
  # A day of slack covers any time zone offset between UTC and local time.
  defp list_overrides_relevant_at(at) do
    from_local = at |> local_naive() |> NaiveDateTime.add(-1, :day)

    Repo.all(from o in Override, where: o.ends_at > ^from_local, preload: :person)
  end

  def get_override!(id), do: Override |> Repo.get!(id) |> Repo.preload(:person)

  def create_override(attrs) do
    %Override{}
    |> Override.changeset(attrs)
    |> Repo.insert()
    |> broadcast()
  end

  def delete_override(%Override{} = override) do
    override
    |> Repo.delete()
    |> broadcast()
  end

  def change_override(%Override{} = override, attrs \\ %{}) do
    Override.changeset(override, attrs)
  end

  @doc """
  Converts an instant to local wall-clock time (seconds precision).
  """
  def local_naive(%DateTime{} = at) do
    at
    |> DateTime.shift_zone!(time_zone())
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
  end

  defp broadcast({:ok, record} = result) do
    Phoenix.PubSub.broadcast(Hermes.PubSub, @topic, {:schedule_changed, record})
    result
  end

  defp broadcast(error), do: error
end
