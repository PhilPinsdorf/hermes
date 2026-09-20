defmodule HermesWeb.ScheduleGridTest do
  use ExUnit.Case, async: true

  alias Hermes.Directory.Person
  alias Hermes.Schedule.Shift
  alias HermesWeb.ScheduleGrid

  defp shift(id, day, from, to) do
    %Shift{
      id: id,
      day_of_week: day,
      starts_at: from,
      ends_at: to,
      active: true,
      person: %Person{id: id, name: "P#{id}"}
    }
  end

  describe "segments/1" do
    test "a daytime shift is one segment" do
      assert [seg] = ScheduleGrid.segments(shift(1, 1, ~T[08:00:00], ~T[16:00:00]))
      assert {seg.day, seg.from, seg.to} == {1, 480, 960}
      refute seg.continues? or seg.continued?
    end

    test "an overnight shift continues in the next day's column" do
      assert [first, spill] = ScheduleGrid.segments(shift(1, 2, ~T[22:00:00], ~T[06:00:00]))
      assert {first.day, first.from, first.to, first.continues?} == {2, 1320, 1440, true}
      assert {spill.day, spill.from, spill.to, spill.continued?} == {3, 0, 360, true}
    end

    test "Sunday night wraps to Monday" do
      assert [_, spill] = ScheduleGrid.segments(shift(1, 7, ~T[20:00:00], ~T[07:00:00]))
      assert spill.day == 1
    end

    test "a shift ending at midnight has no spill segment" do
      assert [seg] = ScheduleGrid.segments(shift(1, 1, ~T[18:00:00], ~T[00:00:00]))
      assert {seg.from, seg.to, seg.continues?} == {1080, 1440, false}
    end

    test "a 24h shift covers the rest of the day and the next morning" do
      assert [first, spill] = ScheduleGrid.segments(shift(1, 1, ~T[08:00:00], ~T[08:00:00]))
      assert {first.from, first.to} == {480, 1440}
      assert {spill.day, spill.from, spill.to} == {2, 0, 480}
    end
  end

  describe "layout/1" do
    test "has all seven days" do
      assert ScheduleGrid.layout([]) |> Map.keys() |> Enum.sort() == Enum.to_list(1..7)
    end

    test "puts overlapping segments side by side" do
      layout =
        ScheduleGrid.layout([
          shift(1, 1, ~T[08:00:00], ~T[16:00:00]),
          shift(2, 1, ~T[12:00:00], ~T[20:00:00]),
          shift(3, 1, ~T[17:00:00], ~T[22:00:00])
        ])

      lanes = Map.new(layout[1], &{&1.shift.id, &1.lane})
      assert lanes == %{1 => 0, 2 => 1, 3 => 0}
      assert Enum.all?(layout[1], &(&1.lanes == 2))
    end

    test "non-overlapping segments share one lane" do
      layout =
        ScheduleGrid.layout([
          shift(1, 1, ~T[08:00:00], ~T[12:00:00]),
          shift(2, 1, ~T[12:00:00], ~T[16:00:00])
        ])

      assert Enum.map(layout[1], &{&1.lane, &1.lanes}) == [{0, 1}, {0, 1}]
    end

    test "the spill of Sunday night shares Monday with Monday's own shifts" do
      layout =
        ScheduleGrid.layout([
          shift(1, 7, ~T[22:00:00], ~T[08:00:00]),
          shift(2, 1, ~T[06:00:00], ~T[14:00:00])
        ])

      assert Enum.map(layout[1], & &1.shift.id) |> Enum.sort() == [1, 2]
      assert Enum.all?(layout[1], &(&1.lanes == 2))
    end
  end

  describe "formatting" do
    test "format_minutes/1" do
      assert ScheduleGrid.format_minutes(0) == "00:00"
      assert ScheduleGrid.format_minutes(510) == "08:30"
      assert ScheduleGrid.format_minutes(1440) == "24:00"
    end

    test "segment_style/1 positions by percent of the day" do
      [seg] = ScheduleGrid.layout([shift(1, 1, ~T[06:00:00], ~T[12:00:00])])[1]
      style = ScheduleGrid.segment_style(seg)
      assert style =~ "top: 25.0%"
      assert style =~ "height: 25.0%"
      assert style =~ "width: 100.0%"
    end
  end
end
