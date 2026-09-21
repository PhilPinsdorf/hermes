defmodule Hermes.Calls.OccupancyTest do
  use ExUnit.Case, async: false

  alias Hermes.Calls.Occupancy

  defp holder(fun) do
    test = self()

    pid =
      spawn(fn ->
        send(test, {:result, fun.()})

        receive do
          :stop -> :ok
        end
      end)

    result =
      receive do
        {:result, result} -> result
      after
        1_000 -> flunk("holder did not report")
      end

    {pid, result}
  end

  defp stop(pid) do
    ref = Process.monitor(pid)
    send(pid, :stop)

    receive do
      {:DOWN, ^ref, _, _, _} -> :ok
    after
      1_000 -> flunk("holder did not stop")
    end
  end

  describe "people" do
    test "the same person cannot be taken twice" do
      {pid, :ok} = holder(fn -> Occupancy.acquire_person(1) end)

      assert Occupancy.acquire_person(1) == {:error, :busy}
      assert Occupancy.busy_person_ids() == [1]

      stop(pid)
    end

    test "a different person is free" do
      {pid, :ok} = holder(fn -> Occupancy.acquire_person(1) end)

      assert Occupancy.acquire_person(2) == :ok
      assert Enum.sort(Occupancy.busy_person_ids()) == [1, 2]

      Occupancy.release_person(2)
      stop(pid)
    end

    test "releasing frees the person again" do
      assert Occupancy.acquire_person(3) == :ok
      assert Occupancy.release_person(3) == :ok
      assert Occupancy.acquire_person(3) == :ok
      Occupancy.release_person(3)
    end

    test "a dying process frees its people without any cleanup" do
      {pid, :ok} = holder(fn -> Occupancy.acquire_person(4) end)
      assert Occupancy.acquire_person(4) == {:error, :busy}

      Process.exit(pid, :kill)

      wait_until(fn -> Occupancy.acquire_person(4) == :ok end)
      Occupancy.release_person(4)
    end
  end

  describe "channel slots" do
    test "hands out the free slots in order" do
      {a, {:ok, 1}} = holder(fn -> Occupancy.acquire_channel(2) end)
      {b, {:ok, 2}} = holder(fn -> Occupancy.acquire_channel(2) end)

      assert Occupancy.acquire_channel(2) == {:error, :no_channel}
      assert Occupancy.used_channels() == 2

      stop(a)
      stop(b)
    end

    test "a freed slot is handed out again" do
      {:ok, slot} = Occupancy.acquire_channel(2)
      assert Occupancy.release_channel(slot) == :ok
      assert Occupancy.acquire_channel(2) == {:ok, slot}
      Occupancy.release_channel(slot)
    end

    test "a larger budget means more parallel calls" do
      {a, {:ok, 1}} = holder(fn -> Occupancy.acquire_channel(4) end)
      {b, {:ok, 2}} = holder(fn -> Occupancy.acquire_channel(4) end)
      {c, {:ok, 3}} = holder(fn -> Occupancy.acquire_channel(4) end)

      assert {:ok, 4} = Occupancy.acquire_channel(4)
      Occupancy.release_channel(4)

      Enum.each([a, b, c], &stop/1)
    end

    test "concurrent acquisitions never hand out the same slot" do
      # Every process keeps its slot until all of them have tried.
      holders = for _ <- 1..20, do: holder(fn -> Occupancy.acquire_channel(8) end)
      results = Enum.map(holders, fn {_pid, result} -> result end)

      slots = for {:ok, slot} <- results, do: slot
      assert length(slots) == 8, "expected exactly the 8 slots to be handed out"
      assert Enum.sort(slots) == Enum.to_list(1..8)
      assert Enum.count(results, &(&1 == {:error, :no_channel})) == 12

      Enum.each(holders, fn {pid, _} -> stop(pid) end)
      wait_until(fn -> Occupancy.used_channels() == 0 end)
    end
  end

  defp wait_until(fun, attempts \\ 50) do
    cond do
      fun.() -> :ok
      attempts == 0 -> flunk("condition never became true")
      true -> Process.sleep(10) && wait_until(fun, attempts - 1)
    end
  end
end
