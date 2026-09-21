defmodule Hermes.Calls.Log do
  @moduledoc """
  The call log: writing finished calls, reading them with filters, and the
  retention rules (phone numbers are personal data).
  """

  import Ecto.Query, warn: false

  alias Hermes.Calls
  alias Hermes.Calls.{CallAttempt, CallLog}
  alias Hermes.Repo

  @doc """
  Writes a finished call. Attempts are given as
  `[%{person_id:, person_name:, outcome:}]` in the order they were tried.
  """
  def record(attrs) do
    attempts =
      attrs
      |> Map.get(:attempts, [])
      |> Enum.with_index(1)
      |> Enum.map(fn {attempt, position} -> Map.put(attempt, :position, position) end)

    %CallLog{}
    |> CallLog.changeset(Map.put(attrs, :attempts, attempts))
    |> Repo.insert()
    |> broadcast()
  end

  @doc """
  Lists calls, newest first.

  Filters: `:result`, `:person_id`, `:from`, `:to` (dates in local time),
  `:limit` and `:offset`.
  """
  def list_calls(filters \\ %{}) do
    CallLog
    |> filter_by(filters)
    |> order_by([c], desc: c.started_at, desc: c.id)
    |> limit(^Map.get(filters, :limit, 50))
    |> offset(^Map.get(filters, :offset, 0))
    |> preload([:person, attempts: :person])
    |> Repo.all()
  end

  @doc "Number of calls matching the filters."
  def count_calls(filters \\ %{}) do
    CallLog
    |> filter_by(filters)
    |> Repo.aggregate(:count)
  end

  @doc "A single call with everything belonging to it."
  def get_call!(id) do
    CallLog
    |> Repo.get!(id)
    |> Repo.preload([:person, attempts: :person])
  end

  @doc """
  How often each outcome happened per person, newest `days` days — this is
  where a phone whose voicemail keeps answering becomes visible.
  """
  def attempt_stats(days \\ 30) do
    since = DateTime.add(DateTime.utc_now(), -days, :day)

    from(a in CallAttempt,
      join: c in assoc(a, :call_log),
      where: c.started_at >= ^since,
      group_by: [a.person_name, a.outcome],
      select: {a.person_name, a.outcome, count(a.id)},
      order_by: [asc: a.person_name]
    )
    |> Repo.all()
  end

  defp filter_by(query, filters) do
    Enum.reduce(filters, query, fn
      {:result, result}, query when result not in [nil, "", :all] ->
        where(query, [c], c.result == ^to_enum(result))

      {:person_id, person_id}, query when person_id not in [nil, "", :all] ->
        where(query, [c], c.person_id == ^person_id)

      {:from, %Date{} = from}, query ->
        where(query, [c], c.started_at >= ^start_of_day(from))

      {:to, %Date{} = to}, query ->
        where(query, [c], c.started_at < ^start_of_day(Date.add(to, 1)))

      _other, query ->
        query
    end)
  end

  defp to_enum(value) when is_atom(value), do: value
  defp to_enum(value) when is_binary(value), do: String.to_existing_atom(value)

  # Local midnight, so a filter day means what it says on the wall clock.
  defp start_of_day(date) do
    date
    |> DateTime.new!(~T[00:00:00], Hermes.Schedule.time_zone())
    |> DateTime.shift_zone!("Etc/UTC")
  end

  ## Retention

  @doc """
  Applies the retention rules:

    * calls older than `retention_days` are deleted entirely
    * calls older than `anonymize_after_days` keep their statistics but lose
      the caller's number

  Returns `%{deleted: n, anonymized: n}`.
  """
  def apply_retention(retention_days, anonymize_after_days \\ nil) do
    now = DateTime.utc_now()

    {deleted, _} =
      from(c in CallLog, where: c.started_at < ^DateTime.add(now, -retention_days, :day))
      |> Repo.delete_all()

    anonymized =
      if anonymize_after_days do
        {count, _} =
          from(c in CallLog,
            where: c.started_at < ^DateTime.add(now, -anonymize_after_days, :day),
            where: not is_nil(c.caller_number)
          )
          |> Repo.update_all(set: [caller_number: nil])

        count
      else
        0
      end

    %{deleted: deleted, anonymized: anonymized}
  end

  defp broadcast({:ok, call_log} = result) do
    Calls.broadcast({:call_logged, call_log.id})
    result
  end

  defp broadcast(error), do: error
end
