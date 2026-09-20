defmodule Hermes.ScheduleTest do
  use Hermes.DataCase, async: true

  alias Hermes.Directory
  alias Hermes.Schedule
  alias Hermes.Schedule.{Override, Shift}

  import Hermes.DirectoryFixtures
  import Hermes.ScheduleFixtures

  describe "shifts" do
    test "create_shift/1 accepts HH:MM times from a time input" do
      person = person_fixture()

      assert {:ok, %Shift{} = shift} =
               Schedule.create_shift(%{
                 "person_id" => person.id,
                 "day_of_week" => "3",
                 "starts_at" => "22:00",
                 "ends_at" => "06:00"
               })

      assert shift.starts_at == ~T[22:00:00]
      assert shift.ends_at == ~T[06:00:00]
      assert Shift.overnight?(shift)
      assert Shift.duration_minutes(shift) == 480
    end

    test "create_shift/1 drops seconds" do
      assert %{starts_at: ~T[08:15:00]} = shift_fixture(starts_at: ~T[08:15:42])
    end

    test "create_shift/1 validates the weekday and required fields" do
      assert {:error, changeset} = Schedule.create_shift(%{day_of_week: 8})
      errors = errors_on(changeset)
      assert errors.day_of_week == ["is invalid"]
      assert errors.person_id == ["can't be blank"]
      assert errors.starts_at == ["can't be blank"]
    end

    test "create_shift/1 rejects an unknown person" do
      assert {:error, changeset} =
               Schedule.create_shift(%{
                 person_id: -1,
                 day_of_week: 1,
                 starts_at: ~T[08:00:00],
                 ends_at: ~T[09:00:00]
               })

      assert errors_on(changeset).person == ["does not exist"]
    end

    test "list_shifts/0 orders by day and start, with person preloaded" do
      b = shift_fixture(day_of_week: 2, starts_at: ~T[08:00:00])
      a = shift_fixture(day_of_week: 1, starts_at: ~T[12:00:00])
      c = shift_fixture(day_of_week: 1, starts_at: ~T[06:00:00])

      assert [%{id: c_id, person: %{}}, %{id: a_id}, %{id: b_id}] = Schedule.list_shifts()
      assert {c_id, a_id, b_id} == {c.id, a.id, b.id}
    end

    test "update and delete broadcast a change" do
      Schedule.subscribe()
      shift = shift_fixture()
      assert_receive {:schedule_changed, _}

      {:ok, _} = Schedule.update_shift(shift, %{position: 3})
      assert_receive {:schedule_changed, %Shift{position: 3}}

      {:ok, _} = Schedule.delete_shift(shift)
      assert_receive {:schedule_changed, _}
      assert Schedule.list_shifts() == []
    end

    test "deleting a person deletes their shifts and overrides" do
      shift = shift_fixture()
      override_fixture(person_id: shift.person_id)

      {:ok, _} = Directory.delete_person(shift.person)

      assert Schedule.list_shifts() == []
      assert Schedule.list_upcoming_overrides() == []
    end
  end

  describe "overrides" do
    test "create_override/1 accepts datetime-local values" do
      person = person_fixture()

      assert {:ok, %Override{} = o} =
               Schedule.create_override(%{
                 "person_id" => person.id,
                 "kind" => "add",
                 "starts_at" => "2099-05-01T08:00",
                 "ends_at" => "2099-05-01T18:30"
               })

      assert o.starts_at == ~N[2099-05-01 08:00:00]
      assert o.ends_at == ~N[2099-05-01 18:30:00]
      assert o.kind == :add
    end

    test "create_override/1 requires the end after the start" do
      person = person_fixture()

      assert {:error, changeset} =
               Schedule.create_override(%{
                 person_id: person.id,
                 kind: :block,
                 starts_at: ~N[2099-05-02 08:00:00],
                 ends_at: ~N[2099-05-01 08:00:00]
               })

      assert errors_on(changeset).ends_at == ["muss nach dem Beginn liegen"]
    end

    test "list_upcoming_overrides/1 hides past exceptions" do
      past =
        override_fixture(starts_at: ~N[2020-01-01 00:00:00], ends_at: ~N[2020-01-02 00:00:00])

      future = override_fixture()

      ids = Enum.map(Schedule.list_upcoming_overrides(), & &1.id)
      assert future.id in ids
      refute past.id in ids
    end

    test "list_upcoming_overrides/1 includes a running exception" do
      running =
        override_fixture(starts_at: ~N[2020-01-01 00:00:00], ends_at: ~N[2099-01-01 00:00:00])

      assert [%{id: id}] = Schedule.list_upcoming_overrides()
      assert id == running.id
    end
  end

  describe "status/1" do
    test "resolves the stored plan at a given instant" do
      anna = person_fixture(name: "Anna")
      bert = person_fixture(name: "Bert")
      # Monday 08-16 Anna, Monday 16 - Tuesday 08 Bert
      shift_fixture(
        person_id: anna.id,
        day_of_week: 1,
        starts_at: ~T[08:00:00],
        ends_at: ~T[16:00:00]
      )

      shift_fixture(
        person_id: bert.id,
        day_of_week: 1,
        starts_at: ~T[16:00:00],
        ends_at: ~T[08:00:00]
      )

      # Monday 2026-09-14 12:00 Berlin = 10:00 UTC
      status = Schedule.status(~U[2026-09-14 10:00:00Z])
      assert Enum.map(status.on_duty, & &1.name) == ["Anna"]
      assert {at, [%{name: "Bert"}]} = status.next_change
      assert at == DateTime.shift_zone!(~U[2026-09-14 14:00:00Z], "Europe/Berlin")

      # Tuesday 03:00 Berlin: still Bert's night
      assert %{on_duty: [%{name: "Bert"}]} = Schedule.status(~U[2026-09-15 01:00:00Z])
    end

    test "applies stored overrides" do
      anna = person_fixture(name: "Anna")
      shift_fixture(person_id: anna.id, day_of_week: 1)

      override_fixture(
        person_id: anna.id,
        kind: :block,
        starts_at: ~N[2026-09-14 00:00:00],
        ends_at: ~N[2026-09-15 00:00:00]
      )

      assert %{on_duty: []} = Schedule.status(~U[2026-09-14 10:00:00Z])
      assert %{on_duty: [_]} = Schedule.status(~U[2026-09-21 10:00:00Z])
    end

    test "with nothing planned nobody is on duty" do
      assert %{on_duty: [], next_change: nil} = Schedule.status()
    end
  end

  describe "local_naive/1" do
    test "converts to Berlin wall-clock time" do
      assert Schedule.local_naive(~U[2026-01-15 12:00:00Z]) == ~N[2026-01-15 13:00:00]
      assert Schedule.local_naive(~U[2026-07-15 12:00:00Z]) == ~N[2026-07-15 14:00:00]
    end
  end
end
