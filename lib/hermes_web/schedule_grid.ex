defmodule HermesWeb.ScheduleGrid do
  @moduledoc """
  Pure layout for the weekly schedule grid: splits shifts into per-day
  segments (overnight shifts continue into the next day's column, Sunday
  wraps to Monday) and assigns side-by-side lanes to overlapping segments.
  """

  alias Hermes.Schedule.Shift

  @day_minutes 1440

  defmodule Segment do
    @moduledoc false
    defstruct [:shift, :day, :from, :to, :lane, lanes: 1, continued?: false, continues?: false]
  end

  @day_names ~w(Montag Dienstag Mittwoch Donnerstag Freitag Samstag Sonntag)
  @day_abbrs ~w(Mo Di Mi Do Fr Sa So)

  def day_name(day) when day in 1..7, do: Enum.at(@day_names, day - 1)
  def day_abbr(day) when day in 1..7, do: Enum.at(@day_abbrs, day - 1)
  def next_day(7), do: 1
  def next_day(day), do: day + 1

  @doc """
  Returns `%{day => [%Segment{}]}` for all seven days (1 = Monday).
  """
  def layout(shifts) do
    segments = Enum.flat_map(shifts, &segments/1)

    for day <- 1..7, into: %{} do
      {day, segments |> Enum.filter(&(&1.day == day)) |> assign_lanes()}
    end
  end

  @doc """
  Splits one shift into its day segments, in minutes since midnight.
  """
  def segments(%Shift{} = shift) do
    from = minutes(shift.starts_at)
    to = minutes(shift.ends_at)

    if Shift.overnight?(shift) do
      first = %Segment{shift: shift, day: shift.day_of_week, from: from, to: @day_minutes}

      spill = %Segment{
        shift: shift,
        day: next_day(shift.day_of_week),
        from: 0,
        to: to,
        continued?: true
      }

      if to == 0, do: [first], else: [%{first | continues?: true}, spill]
    else
      [%Segment{shift: shift, day: shift.day_of_week, from: from, to: to}]
    end
  end

  # Greedy interval partitioning. Every segment in a day gets the same lane
  # count, so widths line up; a day rarely has more than two or three lanes.
  defp assign_lanes(segments) do
    {placed, lane_ends} =
      segments
      |> Enum.sort_by(&{&1.from, -&1.to})
      |> Enum.map_reduce([], fn seg, lane_ends ->
        case Enum.find_index(lane_ends, &(&1 <= seg.from)) do
          nil -> {%{seg | lane: length(lane_ends)}, lane_ends ++ [seg.to]}
          lane -> {%{seg | lane: lane}, List.replace_at(lane_ends, lane, seg.to)}
        end
      end)

    lanes = max(length(lane_ends), 1)
    Enum.map(placed, &%{&1 | lanes: lanes})
  end

  def minutes(%Time{hour: h, minute: m}), do: h * 60 + m

  @doc """
  Formats minutes since midnight as `HH:MM` (1440 → `24:00`).
  """
  def format_minutes(minutes) do
    h = div(minutes, 60) |> Integer.to_string() |> String.pad_leading(2, "0")
    m = rem(minutes, 60) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{h}:#{m}"
  end

  def format_time(%Time{} = t), do: t |> minutes() |> format_minutes()

  @doc """
  CSS for positioning a segment inside its day column (percent of the day).
  """
  def segment_style(%Segment{} = seg) do
    top = seg.from / @day_minutes * 100
    height = (seg.to - seg.from) / @day_minutes * 100
    width = 100 / seg.lanes
    left = seg.lane * width

    "top: #{pct(top)}; height: #{pct(height)}; left: #{pct(left)}; width: #{pct(width)}; " <>
      person_color_style(seg.shift.person)
  end

  @doc """
  A stable color per person, readable in light and dark themes.
  """
  def person_color_style(%{id: id}) do
    hue = rem(id * 137, 360)

    "--person-hue: #{hue}; background-color: hsl(#{hue} 70% 50% / 0.22); border-color: hsl(#{hue} 65% 45%);"
  end

  defp pct(value), do: "#{Float.round(value * 1.0, 4)}%"
end
