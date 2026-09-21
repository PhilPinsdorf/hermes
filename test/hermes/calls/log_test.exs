defmodule Hermes.Calls.LogTest do
  use Hermes.DataCase, async: true

  import Hermes.DirectoryFixtures

  alias Hermes.Calls.Log

  defp record(attrs \\ %{}) do
    {:ok, call} =
      attrs
      |> Enum.into(%{
        channel_id: "chan-#{System.unique_integer([:positive])}",
        caller_number: "+4915112345678",
        started_at: DateTime.utc_now() |> DateTime.truncate(:second),
        result: :announced
      })
      |> Log.record()

    call
  end

  describe "record/1" do
    test "writes a call with its attempts in order" do
      anna = person_fixture(name: "Anna")
      bert = person_fixture(name: "Bert")

      call =
        record(%{
          result: :bridged,
          person_id: bert.id,
          talk_seconds: 65,
          total_seconds: 95,
          attempts: [
            %{person_id: anna.id, person_name: "Anna", outcome: :no_confirmation},
            %{person_id: bert.id, person_name: "Bert", outcome: :confirmed}
          ]
        })

      call = Log.get_call!(call.id)
      assert call.result == :bridged
      assert call.person.name == "Bert"

      assert Enum.map(call.attempts, &{&1.position, &1.person_name, &1.outcome}) == [
               {1, "Anna", :no_confirmation},
               {2, "Bert", :confirmed}
             ]
    end

    test "keeps the attempt readable after the person was deleted" do
      anna = person_fixture(name: "Anna")

      call =
        record(%{attempts: [%{person_id: anna.id, person_name: "Anna", outcome: :busy}]})

      {:ok, _} = Hermes.Directory.delete_person(anna)

      assert [attempt] = Log.get_call!(call.id).attempts
      assert attempt.person_name == "Anna"
      assert attempt.person_id == nil
    end

    test "announces the new entry" do
      Hermes.Calls.subscribe()
      call = record()
      assert_receive {:call_logged, id}
      assert id == call.id
    end

    test "the same channel is not logged twice" do
      record(%{channel_id: "chan-double"})

      assert {:error, changeset} =
               Log.record(%{
                 channel_id: "chan-double",
                 started_at: DateTime.utc_now() |> DateTime.truncate(:second),
                 result: :announced
               })

      assert "has already been taken" in errors_on(changeset).channel_id
    end
  end

  describe "list_calls/1" do
    test "newest first" do
      old = record(%{started_at: ~U[2026-09-01 10:00:00Z]})
      new = record(%{started_at: ~U[2026-09-20 10:00:00Z]})

      assert Enum.map(Log.list_calls(), & &1.id) == [new.id, old.id]
    end

    test "filters by result, person and date range" do
      anna = person_fixture(name: "Anna")

      bridged =
        record(%{result: :bridged, person_id: anna.id, started_at: ~U[2026-09-10 10:00:00Z]})

      announced = record(%{result: :announced, started_at: ~U[2026-09-12 10:00:00Z]})

      assert Enum.map(Log.list_calls(%{result: :bridged}), & &1.id) == [bridged.id]
      assert Enum.map(Log.list_calls(%{result: "announced"}), & &1.id) == [announced.id]
      assert Enum.map(Log.list_calls(%{person_id: anna.id}), & &1.id) == [bridged.id]

      assert Enum.map(Log.list_calls(%{from: ~D[2026-09-11]}), & &1.id) == [announced.id]
      assert Enum.map(Log.list_calls(%{to: ~D[2026-09-11]}), & &1.id) == [bridged.id]
      assert Log.list_calls(%{from: ~D[2026-09-10], to: ~D[2026-09-12]}) |> length() == 2
    end

    test "the date filter uses local days" do
      # 2026-09-10 23:30 UTC is already 2026-09-11 in Berlin.
      call = record(%{started_at: ~U[2026-09-10 23:30:00Z]})

      assert Enum.map(Log.list_calls(%{from: ~D[2026-09-11]}), & &1.id) == [call.id]
      assert Log.list_calls(%{to: ~D[2026-09-10]}) == []
    end

    test "paginates and counts" do
      for _ <- 1..5, do: record()

      assert length(Log.list_calls(%{limit: 2})) == 2
      assert length(Log.list_calls(%{limit: 2, offset: 4})) == 1
      assert Log.count_calls() == 5
      assert Log.count_calls(%{result: :bridged}) == 0
    end
  end

  describe "attempt_stats/1" do
    test "counts outcomes per person" do
      anna = person_fixture(name: "Anna")

      record(%{attempts: [%{person_id: anna.id, person_name: "Anna", outcome: :no_confirmation}]})
      record(%{attempts: [%{person_id: anna.id, person_name: "Anna", outcome: :no_confirmation}]})
      record(%{attempts: [%{person_id: anna.id, person_name: "Anna", outcome: :confirmed}]})

      stats = Log.attempt_stats(30)
      assert {"Anna", :no_confirmation, 2} in stats
      assert {"Anna", :confirmed, 1} in stats
    end

    test "ignores calls outside the window" do
      anna = person_fixture(name: "Anna")

      record(%{
        started_at: DateTime.add(DateTime.utc_now(), -60, :day) |> DateTime.truncate(:second),
        attempts: [%{person_id: anna.id, person_name: "Anna", outcome: :busy}]
      })

      assert Log.attempt_stats(30) == []
    end
  end

  describe "apply_retention/2" do
    test "deletes calls older than the retention period" do
      old =
        record(%{
          started_at: DateTime.add(DateTime.utc_now(), -100, :day) |> DateTime.truncate(:second)
        })

      kept = record()

      assert %{deleted: 1} = Log.apply_retention(90)
      assert Enum.map(Log.list_calls(), & &1.id) == [kept.id]
      refute Repo.get(Hermes.Calls.CallLog, old.id)
    end

    test "removes only the caller number of older calls when asked to" do
      older =
        record(%{
          started_at: DateTime.add(DateTime.utc_now(), -40, :day) |> DateTime.truncate(:second)
        })

      recent = record()

      assert %{deleted: 0, anonymized: 1} = Log.apply_retention(90, 30)

      assert Repo.get(Hermes.Calls.CallLog, older.id).caller_number == nil
      assert Repo.get(Hermes.Calls.CallLog, recent.id).caller_number == "+4915112345678"
    end

    test "deleting takes the attempts with it" do
      anna = person_fixture(name: "Anna")

      record(%{
        started_at: DateTime.add(DateTime.utc_now(), -100, :day) |> DateTime.truncate(:second),
        attempts: [%{person_id: anna.id, person_name: "Anna", outcome: :busy}]
      })

      Log.apply_retention(90)
      assert Repo.aggregate(Hermes.Calls.CallAttempt, :count) == 0
    end
  end
end
