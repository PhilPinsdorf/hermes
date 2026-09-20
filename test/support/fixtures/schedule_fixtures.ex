defmodule Hermes.ScheduleFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Hermes.Schedule` context.
  """

  import Hermes.DirectoryFixtures

  def shift_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    person_id = Map.get_lazy(attrs, :person_id, fn -> person_fixture().id end)

    {:ok, shift} =
      attrs
      |> Enum.into(%{
        person_id: person_id,
        day_of_week: 1,
        starts_at: ~T[08:00:00],
        ends_at: ~T[16:00:00]
      })
      |> Hermes.Schedule.create_shift()

    Hermes.Schedule.get_shift!(shift.id)
  end

  def override_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    person_id = Map.get_lazy(attrs, :person_id, fn -> person_fixture().id end)

    {:ok, override} =
      attrs
      |> Enum.into(%{
        person_id: person_id,
        kind: :block,
        starts_at: ~N[2099-01-01 00:00:00],
        ends_at: ~N[2099-01-02 00:00:00]
      })
      |> Hermes.Schedule.create_override()

    Hermes.Schedule.get_override!(override.id)
  end
end
