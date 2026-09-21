defmodule Hermes.Calls.Retention do
  @moduledoc """
  Applies the call log retention rules once a day (and once at start).

  The plan called for an Oban job; for a single recurring cleanup in a
  single-instance deployment a small process does the same without a job
  database, its tables and migrations. If Hermes ever grows real background
  work, this is the place to swap in Oban.
  """
  use GenServer

  require Logger

  alias Hermes.Calls.Log
  alias Hermes.Settings

  @interval :timer.hours(24)
  # Not right at boot: let the app come up first.
  @initial_delay :timer.minutes(5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Runs the cleanup now (used by tests and for manual runs)."
  def run_now, do: GenServer.call(__MODULE__, :run, 30_000)

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @interval)
    delay = Keyword.get(opts, :initial_delay, @initial_delay)
    Process.send_after(self(), :run, delay)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:run, state) do
    run()
    Process.send_after(self(), :run, state.interval)
    {:noreply, state}
  end

  @impl true
  def handle_call(:run, _from, state), do: {:reply, run(), state}

  defp run do
    settings = Settings.get()

    result =
      Log.apply_retention(
        settings.call_log_retention_days,
        settings.call_log_anonymize_after_days
      )

    pruned = Hermes.Sounds.prune_variants()

    if pruned > 0 do
      Logger.info("call log retention: #{pruned} cached announcement variants removed")
    end

    if result.deleted > 0 or result.anonymized > 0 do
      Logger.info(
        "call log retention: #{result.deleted} deleted, #{result.anonymized} numbers removed"
      )
    end

    result
  rescue
    error ->
      Logger.error("call log retention failed: #{Exception.message(error)}")
      %{deleted: 0, anonymized: 0}
  end
end
