defmodule Hermes.Calls.RetentionTest do
  use Hermes.DataCase, async: false

  alias Hermes.Calls.{Log, Retention}
  alias Hermes.Settings

  defp record(days_ago) do
    {:ok, call} =
      Log.record(%{
        channel_id: "chan-#{System.unique_integer([:positive])}",
        caller_number: "+4915112345678",
        started_at:
          DateTime.utc_now() |> DateTime.add(-days_ago, :day) |> DateTime.truncate(:second),
        result: :announced
      })

    call
  end

  test "deletes and anonymizes according to the settings" do
    {:ok, _} = Settings.update(%{call_log_retention_days: 90, call_log_anonymize_after_days: 30})

    old = record(100)
    middle = record(40)
    recent = record(1)

    assert %{deleted: 1, anonymized: 1} = Retention.run_now()

    refute Repo.get(Hermes.Calls.CallLog, old.id)
    assert Repo.get(Hermes.Calls.CallLog, middle.id).caller_number == nil
    assert Repo.get(Hermes.Calls.CallLog, recent.id).caller_number == "+4915112345678"
  end

  test "keeps the numbers when anonymizing is switched off" do
    {:ok, _} = Settings.update(%{call_log_retention_days: 90, call_log_anonymize_after_days: nil})
    call = record(40)

    assert %{deleted: 0, anonymized: 0} = Retention.run_now()
    assert Repo.get(Hermes.Calls.CallLog, call.id).caller_number == "+4915112345678"
  end
end
