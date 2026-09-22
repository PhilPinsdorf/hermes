defmodule Hermes.Schedule.Resolver do
  @moduledoc """
  Pure duty-roster logic: who is on duty at a given instant, and when that
  changes next. No database, no clock, no process state — everything comes in
  as arguments, which makes midnight and DST cases directly testable.

  ## Time semantics

  Shifts and overrides are **local wall-clock times** in the configured time
  zone. An instant is converted to local time first and then compared against
  the wall-clock intervals. Consequences around DST in `Europe/Berlin`:

    * spring forward (02:00 → 03:00): a 22:00–06:00 shift is one hour shorter;
      a shift that lies entirely inside 02:00–03:00 never takes effect
    * fall back (03:00 → 02:00): 22:00–06:00 is one hour longer; a shift
      covering 02:30 is active during both occurrences of 02:30

  ## Ordering

  The result is ordered by who should be called first:

    1. people from the weekly plan, by `shift.position`
    2. people added by an `:add` override, after everyone in the plan — an
       exception is a stand-in, so the roster is asked first

  Someone who is both in the plan and added by an override is called **once**,
  at their position in the plan — never a second time at the end.

  Inactive people and inactive shifts are ignored; a `:block` override removes
  a person regardless of source.

  Two people with the same position are a tie, and who is asked first then
  depends on the caller:

    * `on_duty_at/4` keeps a fixed order (person position, then name) — the
      overview and `next_change/5` must not jitter between two renderings
    * `call_order/4` shuffles the tie, so the same person is not the first to
      be rung every single time
  """

  alias Hermes.Directory.Person
  alias Hermes.Schedule.{Override, Shift}

  @doc """
  Returns the people on duty at `at` in a fixed order — for the overview and
  for `next_change/5`, which compares two lists and must not see a change that
  is only a reshuffle.

  `shifts` and `overrides` must have `:person` preloaded.
  """
  @spec on_duty_at(DateTime.t(), [Shift.t()], [Override.t()], String.t()) :: [Person.t()]
  def on_duty_at(%DateTime{} = at, shifts, overrides, time_zone) do
    at |> ranked(shifts, overrides, time_zone) |> settle(:fixed)
  end

  @doc """
  The same people, but ties are rolled: among equal positions nobody is
  permanently first. This is the order a call rings through.
  """
  @spec call_order(DateTime.t(), [Shift.t()], [Override.t()], String.t()) :: [Person.t()]
  def call_order(%DateTime{} = at, shifts, overrides, time_zone) do
    at |> ranked(shifts, overrides, time_zone) |> settle(:rolled)
  end

  # Everyone on duty, each tagged with {source, position}: source 0 is the
  # weekly plan, source 1 an `:add` override, which comes after it.
  defp ranked(at, shifts, overrides, time_zone) do
    local = at |> DateTime.shift_zone!(time_zone) |> DateTime.to_naive()

    blocked =
      for %Override{kind: :block} = o <- overrides,
          override_covers?(o, local),
          into: MapSet.new(),
          do: o.person_id

    from_shifts =
      for %Shift{active: true} = s <- shifts,
          shift_covers?(s, local),
          do: {{0, s.position}, s.person}

    added =
      for %Override{kind: :add} = o <- overrides,
          override_covers?(o, local),
          do: {{1, 0}, o.person}

    Enum.filter(from_shifts ++ added, fn {_rank, person} ->
      person.active and not MapSet.member?(blocked, person.id)
    end)
  end

  # Sorting by rank is stable, so shuffling beforehand only reorders people who
  # share a rank. Deduplication comes last and therefore keeps the best rank —
  # that is what stops someone in both the plan and an override being rung
  # twice.
  defp settle(ranked, tie) do
    ranked
    |> pre_sort(tie)
    |> Enum.sort_by(fn {rank, _person} -> rank end)
    |> Enum.uniq_by(fn {_rank, person} -> person.id end)
    |> Enum.map(fn {_rank, person} -> person end)
  end

  defp pre_sort(ranked, :rolled), do: Enum.shuffle(ranked)

  defp pre_sort(ranked, :fixed),
    do: Enum.sort_by(ranked, fn {_rank, person} -> {person.position, person.name} end)

  @doc """
  Returns `{instant, people}` for the next moment after `at` at which the
  on-duty list changes (who, or in which order), or `nil` if nothing changes
  within `horizon_days`.
  """
  @spec next_change(DateTime.t(), [Shift.t()], [Override.t()], String.t(), pos_integer()) ::
          {DateTime.t(), [Person.t()]} | nil
  def next_change(%DateTime{} = at, shifts, overrides, time_zone, horizon_days \\ 8) do
    current = ids(on_duty_at(at, shifts, overrides, time_zone))
    today = at |> DateTime.shift_zone!(time_zone) |> DateTime.to_date()

    shift_bounds =
      for date <- Date.range(Date.add(today, -1), Date.add(today, horizon_days)),
          %Shift{active: true} = s <- shifts,
          s.day_of_week == Date.day_of_week(date),
          naive <- shift_bounds(s, date),
          do: naive

    override_bounds = Enum.flat_map(overrides, &[&1.starts_at, &1.ends_at])
    limit = DateTime.add(at, horizon_days, :day)

    (shift_bounds ++ override_bounds)
    |> Enum.flat_map(&to_instants(&1, time_zone))
    |> Enum.filter(&(DateTime.after?(&1, at) and not DateTime.after?(&1, limit)))
    |> Enum.sort(DateTime)
    |> Enum.dedup()
    |> Enum.find_value(fn instant ->
      people = on_duty_at(instant, shifts, overrides, time_zone)
      if ids(people) != current, do: {instant, people}
    end)
  end

  @doc """
  True when `shift` covers the local wall-clock time `local`.
  """
  @spec shift_covers?(Shift.t(), NaiveDateTime.t()) :: boolean()
  def shift_covers?(%Shift{} = shift, %NaiveDateTime{} = local) do
    date = NaiveDateTime.to_date(local)
    time = NaiveDateTime.to_time(local)
    today = Date.day_of_week(date)
    yesterday = date |> Date.add(-1) |> Date.day_of_week()

    cond do
      # the part that starts today
      shift.day_of_week == today ->
        at_or_after?(time, shift.starts_at) and
          (Shift.overnight?(shift) or before?(time, shift.ends_at))

      # the part of yesterday's overnight shift that spills into today
      shift.day_of_week == yesterday and Shift.overnight?(shift) ->
        before?(time, shift.ends_at)

      true ->
        false
    end
  end

  defp override_covers?(%Override{starts_at: s, ends_at: e}, local) do
    NaiveDateTime.compare(local, s) != :lt and NaiveDateTime.compare(local, e) == :lt
  end

  # Wall-clock start and end of `shift` when it starts on `date`.
  defp shift_bounds(shift, date) do
    end_date = if Shift.overnight?(shift), do: Date.add(date, 1), else: date
    [NaiveDateTime.new!(date, shift.starts_at), NaiveDateTime.new!(end_date, shift.ends_at)]
  end

  # A wall-clock time can map to one instant, two (fall back) or none (spring
  # forward gap — the change then happens at the first instant after the gap).
  defp to_instants(naive, time_zone) do
    case DateTime.from_naive(naive, time_zone) do
      {:ok, dt} -> [dt]
      {:ambiguous, first, second} -> [first, second]
      {:gap, _before, after_gap} -> [after_gap]
    end
  end

  defp at_or_after?(time, bound), do: Time.compare(time, bound) != :lt
  defp before?(time, bound), do: Time.compare(time, bound) == :lt

  defp ids(people), do: Enum.map(people, & &1.id)
end
