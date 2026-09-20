defmodule Hermes.Schedule.ResolverTest do
  @moduledoc """
  Pure tests: no database, no clock mocking. Instants are given explicitly,
  shifts and overrides are plain structs.
  """
  use ExUnit.Case, async: true

  alias Hermes.Directory.Person
  alias Hermes.Schedule.{Override, Resolver, Shift}

  @tz "Europe/Berlin"

  # 2026-09-14 is a Monday. Weekdays: 1 = Mon ... 7 = Sun.
  @mon ~D[2026-09-14]

  defp person(id, attrs \\ []) do
    struct!(%Person{id: id, name: "P#{id}", position: 0, active: true}, attrs)
  end

  defp shift(person, day, from, to, attrs \\ []) do
    struct!(
      %Shift{
        person: person,
        person_id: person.id,
        day_of_week: day,
        starts_at: Time.from_iso8601!(from <> ":00"),
        ends_at: Time.from_iso8601!(to <> ":00"),
        position: 0,
        active: true
      },
      attrs
    )
  end

  defp override(person, kind, from, to) do
    %Override{
      person: person,
      person_id: person.id,
      kind: kind,
      starts_at: NaiveDateTime.from_iso8601!(from <> ":00"),
      ends_at: NaiveDateTime.from_iso8601!(to <> ":00")
    }
  end

  # Local wall-clock time in Berlin -> instant. Raises on gaps/ambiguity so a
  # test never silently picks the wrong instant.
  defp at(date, time) do
    {:ok, dt} = DateTime.new(date, Time.from_iso8601!(time <> ":00"), @tz)
    dt
  end

  defp on_duty(instant, shifts, overrides \\ []) do
    instant |> Resolver.on_duty_at(shifts, overrides, @tz) |> Enum.map(& &1.id)
  end

  describe "plain daytime shifts" do
    setup do
      anna = person(1)
      %{anna: anna, shifts: [shift(anna, 1, "08:00", "16:00")]}
    end

    test "covers the interval on its weekday", %{shifts: shifts} do
      assert on_duty(at(@mon, "08:00"), shifts) == [1]
      assert on_duty(at(@mon, "12:00"), shifts) == [1]
      assert on_duty(at(@mon, "15:59"), shifts) == [1]
    end

    test "is half-open: the end minute is no longer covered", %{shifts: shifts} do
      assert on_duty(at(@mon, "16:00"), shifts) == []
      assert on_duty(at(@mon, "07:59"), shifts) == []
    end

    test "does not apply on other weekdays", %{shifts: shifts} do
      assert on_duty(at(Date.add(@mon, 1), "12:00"), shifts) == []
      assert on_duty(at(Date.add(@mon, 7), "12:00"), shifts) == [1]
    end

    test "accepts instants in any zone", %{shifts: shifts} do
      # 10:00 UTC on a summer Monday is 12:00 in Berlin
      assert on_duty(~U[2026-09-14 10:00:00Z], shifts) == [1]
      # 15:00 UTC is 17:00 in Berlin: already over
      assert on_duty(~U[2026-09-14 15:00:00Z], shifts) == []
    end
  end

  describe "shifts across midnight" do
    setup do
      nacht = person(1)
      # Monday 22:00 -> Tuesday 06:00
      %{shifts: [shift(nacht, 1, "22:00", "06:00")]}
    end

    test "covers the evening of the start day", %{shifts: shifts} do
      assert on_duty(at(@mon, "21:59"), shifts) == []
      assert on_duty(at(@mon, "22:00"), shifts) == [1]
      assert on_duty(at(@mon, "23:59"), shifts) == [1]
    end

    test "continues into the morning of the next day", %{shifts: shifts} do
      tue = Date.add(@mon, 1)
      assert on_duty(at(tue, "00:00"), shifts) == [1]
      assert on_duty(at(tue, "05:59"), shifts) == [1]
      assert on_duty(at(tue, "06:00"), shifts) == []
    end

    test "does not cover the morning of its own start day", %{shifts: shifts} do
      assert on_duty(at(@mon, "03:00"), shifts) == []
    end

    test "Sunday night wraps into Monday morning" do
      p = person(1)
      shifts = [shift(p, 7, "20:00", "07:00")]
      sun = Date.add(@mon, 6)

      assert on_duty(at(sun, "23:00"), shifts) == [1]
      assert on_duty(at(Date.add(sun, 1), "06:30"), shifts) == [1]
      assert on_duty(at(Date.add(sun, 1), "07:00"), shifts) == []
      # and the Monday morning before that Sunday is covered by the previous week's Sunday
      assert on_duty(at(@mon, "06:30"), shifts) == [1]
    end

    test "a shift ending exactly at midnight does not spill over" do
      p = person(1)
      shifts = [shift(p, 1, "18:00", "00:00")]

      assert on_duty(at(@mon, "23:59"), shifts) == [1]
      assert on_duty(at(Date.add(@mon, 1), "00:00"), shifts) == []
    end

    test "equal start and end means a full 24 hours" do
      p = person(1)
      shifts = [shift(p, 1, "08:00", "08:00")]
      tue = Date.add(@mon, 1)

      assert on_duty(at(@mon, "07:59"), shifts) == []
      assert on_duty(at(@mon, "08:00"), shifts) == [1]
      assert on_duty(at(tue, "07:59"), shifts) == [1]
      assert on_duty(at(tue, "08:00"), shifts) == []
    end

    test "00:00 to 00:00 is the whole day" do
      p = person(1)
      shifts = [shift(p, 1, "00:00", "00:00")]

      assert on_duty(at(@mon, "00:00"), shifts) == [1]
      assert on_duty(at(@mon, "23:59"), shifts) == [1]
      assert on_duty(at(Date.add(@mon, 1), "00:00"), shifts) == []
    end
  end

  describe "DST in Europe/Berlin" do
    # 2026-03-29 (Sun): 02:00 CET -> 03:00 CEST, the hour 02:00-03:00 does not exist.
    # 2026-10-25 (Sun): 03:00 CEST -> 02:00 CET, the hour 02:00-03:00 happens twice.
    @spring ~D[2026-03-29]
    @autumn ~D[2026-10-25]

    test "spring forward: an overnight shift is one hour shorter, but holds its wall-clock ends" do
      p = person(1)
      # Saturday 22:00 -> Sunday 06:00
      shifts = [shift(p, 6, "22:00", "06:00")]

      assert on_duty(~U[2026-03-28 21:00:00Z], shifts) == [1], "22:00 CET"
      assert on_duty(~U[2026-03-29 00:59:59Z], shifts) == [1], "01:59:59 CET"
      assert on_duty(~U[2026-03-29 01:00:00Z], shifts) == [1], "03:00 CEST, right after the gap"
      assert on_duty(~U[2026-03-29 03:59:59Z], shifts) == [1], "05:59:59 CEST"
      assert on_duty(~U[2026-03-29 04:00:00Z], shifts) == [], "06:00 CEST"
    end

    test "spring forward: a shift entirely inside the missing hour never applies" do
      p = person(1)
      shifts = [shift(p, 7, "02:00", "03:00")]

      for minute <- 0..59 do
        instant = DateTime.add(~U[2026-03-29 00:30:00Z], minute, :minute)
        assert on_duty(instant, shifts) == []
      end
    end

    test "spring forward: a shift starting inside the gap starts right after it" do
      p = person(1)
      shifts = [shift(p, 7, "02:30", "08:00")]

      assert on_duty(~U[2026-03-29 00:59:00Z], shifts) == [], "01:59 CET"
      assert on_duty(~U[2026-03-29 01:00:00Z], shifts) == [1], "03:00 CEST"
    end

    test "fall back: an overnight shift is one hour longer" do
      p = person(1)
      # Saturday 22:00 -> Sunday 06:00
      shifts = [shift(p, 6, "22:00", "06:00")]

      assert on_duty(~U[2026-10-24 20:00:00Z], shifts) == [1], "22:00 CEST"
      assert on_duty(~U[2026-10-25 00:30:00Z], shifts) == [1], "02:30 CEST (first)"
      assert on_duty(~U[2026-10-25 01:30:00Z], shifts) == [1], "02:30 CET (second)"
      assert on_duty(~U[2026-10-25 04:59:59Z], shifts) == [1], "05:59:59 CET"
      assert on_duty(~U[2026-10-25 05:00:00Z], shifts) == [], "06:00 CET"
    end

    test "fall back: a shift covering 02:30 applies during both occurrences" do
      p = person(1)
      shifts = [shift(p, 7, "02:00", "03:00")]

      assert on_duty(~U[2026-10-25 00:30:00Z], shifts) == [1], "02:30 CEST"
      assert on_duty(~U[2026-10-25 01:30:00Z], shifts) == [1], "02:30 CET"
      assert on_duty(~U[2026-10-25 02:00:00Z], shifts) == [], "03:00 CET"
    end

    test "fall back: a Saturday-to-Sunday night is wall-clock based on both days" do
      p = person(1)
      shifts = [shift(p, 6, "18:00", "08:00")]

      assert on_duty(at(@autumn, "07:59"), shifts) == [1]
      assert on_duty(at(@autumn, "08:00"), shifts) == []
      assert on_duty(at(@spring, "07:59"), shifts) == [1]
    end
  end

  describe "ordering and filtering" do
    test "orders by shift position, then person position, then name" do
      a = person(1, name: "Zoe", position: 0)
      b = person(2, name: "Anna", position: 5)
      c = person(3, name: "Bert", position: 5)

      shifts = [
        shift(a, 1, "08:00", "16:00", position: 1),
        shift(b, 1, "08:00", "16:00", position: 0),
        shift(c, 1, "08:00", "16:00", position: 0)
      ]

      assert on_duty(at(@mon, "12:00"), shifts) == [2, 3, 1]
    end

    test "combines overlapping shifts" do
      a = person(1)
      b = person(2)
      shifts = [shift(a, 1, "08:00", "16:00"), shift(b, 1, "12:00", "20:00")]

      assert on_duty(at(@mon, "10:00"), shifts) == [1]
      assert on_duty(at(@mon, "13:00"), shifts) |> Enum.sort() == [1, 2]
      assert on_duty(at(@mon, "17:00"), shifts) == [2]
    end

    test "lists a person only once, at their best position" do
      a = person(1)
      b = person(2)

      shifts = [
        shift(a, 1, "08:00", "16:00", position: 5),
        shift(b, 1, "08:00", "16:00", position: 1),
        shift(a, 1, "10:00", "12:00", position: 0)
      ]

      assert on_duty(at(@mon, "11:00"), shifts) == [1, 2]
      assert on_duty(at(@mon, "13:00"), shifts) == [2, 1]
    end

    test "ignores inactive shifts and inactive people" do
      a = person(1)
      b = person(2, active: false)
      shifts = [shift(a, 1, "08:00", "16:00", active: false), shift(b, 1, "08:00", "16:00")]

      assert on_duty(at(@mon, "12:00"), shifts) == []
    end
  end

  describe "overrides" do
    setup do
      anna = person(1)
      bert = person(2)
      %{anna: anna, bert: bert, shifts: [shift(anna, 1, "08:00", "16:00")]}
    end

    test "block removes a person during the interval only", %{anna: anna, shifts: shifts} do
      overrides = [override(anna, :block, "2026-09-14T10:00", "2026-09-14T12:00")]

      assert on_duty(at(@mon, "09:59"), shifts, overrides) == [1]
      assert on_duty(at(@mon, "10:00"), shifts, overrides) == []
      assert on_duty(at(@mon, "12:00"), shifts, overrides) == [1]
    end

    test "a holiday block spans several weeks of shifts", %{anna: anna, shifts: shifts} do
      overrides = [override(anna, :block, "2026-09-14T00:00", "2026-09-28T00:00")]

      assert on_duty(at(@mon, "12:00"), shifts, overrides) == []
      assert on_duty(at(Date.add(@mon, 7), "12:00"), shifts, overrides) == []
      assert on_duty(at(Date.add(@mon, 14), "12:00"), shifts, overrides) == [1]
    end

    test "add puts a person on duty, ahead of shift people", %{bert: bert, shifts: shifts} do
      overrides = [override(bert, :add, "2026-09-14T12:00", "2026-09-14T20:00")]

      assert on_duty(at(@mon, "11:00"), shifts, overrides) == [1]
      assert on_duty(at(@mon, "13:00"), shifts, overrides) == [2, 1]
      assert on_duty(at(@mon, "17:00"), shifts, overrides) == [2]
    end

    test "swap: block one, add another", %{anna: anna, bert: bert, shifts: shifts} do
      overrides = [
        override(anna, :block, "2026-09-14T08:00", "2026-09-14T16:00"),
        override(bert, :add, "2026-09-14T08:00", "2026-09-14T16:00")
      ]

      assert on_duty(at(@mon, "12:00"), shifts, overrides) == [2]
      # the following Monday is back to normal
      assert on_duty(at(Date.add(@mon, 7), "12:00"), shifts, overrides) == [1]
    end

    test "block wins over add for the same person", %{bert: bert, shifts: shifts} do
      overrides = [
        override(bert, :add, "2026-09-14T08:00", "2026-09-14T16:00"),
        override(bert, :block, "2026-09-14T08:00", "2026-09-14T16:00")
      ]

      assert on_duty(at(@mon, "12:00"), shifts, overrides) == [1]
    end

    test "overrides can run across midnight", %{bert: bert} do
      overrides = [override(bert, :add, "2026-09-14T22:00", "2026-09-15T06:00")]

      assert on_duty(at(Date.add(@mon, 1), "03:00"), [], overrides) == [2]
    end

    test "an add override does not revive an inactive person" do
      ghost = person(9, active: false)
      overrides = [override(ghost, :add, "2026-09-14T08:00", "2026-09-14T16:00")]

      assert on_duty(at(@mon, "12:00"), [], overrides) == []
    end
  end

  describe "next_change/5" do
    defp next(instant, shifts, overrides \\ []) do
      case Resolver.next_change(instant, shifts, overrides, @tz) do
        nil -> nil
        {dt, people} -> {DateTime.shift_zone!(dt, @tz), Enum.map(people, & &1.id)}
      end
    end

    test "finds the end of the current shift" do
      p = person(1)
      shifts = [shift(p, 1, "08:00", "16:00")]

      assert {dt, []} = next(at(@mon, "12:00"), shifts)
      assert DateTime.to_naive(dt) == ~N[2026-09-14 16:00:00]
    end

    test "finds the next start, possibly days ahead" do
      p = person(1)
      shifts = [shift(p, 1, "08:00", "16:00")]

      assert {dt, [1]} = next(at(@mon, "17:00"), shifts)
      assert DateTime.to_naive(dt) == ~N[2026-09-21 08:00:00]
    end

    test "skips boundaries that do not change who is on duty" do
      p = person(1)
      # back-to-back shifts of the same person: 08-12, 12-16
      shifts = [shift(p, 1, "08:00", "12:00"), shift(p, 1, "12:00", "16:00")]

      assert {dt, []} = next(at(@mon, "09:00"), shifts)
      assert DateTime.to_naive(dt) == ~N[2026-09-14 16:00:00]
    end

    test "sees handovers across midnight" do
      nacht = person(1)
      frueh = person(2)
      shifts = [shift(nacht, 1, "22:00", "06:00"), shift(frueh, 2, "06:00", "14:00")]

      assert {dt, [2]} = next(at(@mon, "23:00"), shifts)
      assert DateTime.to_naive(dt) == ~N[2026-09-15 06:00:00]
    end

    test "takes overrides into account" do
      anna = person(1)
      bert = person(2)
      shifts = [shift(anna, 1, "08:00", "16:00")]
      overrides = [override(bert, :add, "2026-09-14T10:00", "2026-09-14T11:00")]

      assert {dt, [2, 1]} = next(at(@mon, "09:00"), shifts, overrides)
      assert DateTime.to_naive(dt) == ~N[2026-09-14 10:00:00]
    end

    test "returns nil when nothing is planned" do
      assert next(at(@mon, "09:00"), []) == nil
    end

    test "a change inside the spring-forward gap happens right after the gap" do
      p = person(1)
      shifts = [shift(p, 7, "02:30", "08:00")]

      assert {dt, [1]} = next(~U[2026-03-29 00:00:00Z], shifts)
      assert dt == DateTime.shift_zone!(~U[2026-03-29 01:00:00Z], @tz)
    end
  end

  describe "shift_covers?/2" do
    test "works on wall-clock times directly" do
      p = person(1)
      s = shift(p, 1, "22:00", "06:00")

      assert Resolver.shift_covers?(s, ~N[2026-09-14 23:00:00])
      assert Resolver.shift_covers?(s, ~N[2026-09-15 05:00:00])
      refute Resolver.shift_covers?(s, ~N[2026-09-15 23:00:00])
    end
  end
end
