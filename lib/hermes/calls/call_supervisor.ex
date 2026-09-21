defmodule Hermes.Calls.CallSupervisor do
  @moduledoc """
  One `Hermes.Calls.CallSession` per incoming call.
  """
  use DynamicSupervisor

  require Logger

  alias Hermes.Calls.CallSession

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    # A failed call must not be retried automatically: the caller is long gone.
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 0)
  end

  @doc """
  Starts the session for a channel that just entered the Stasis app.
  """
  def start_call(%{"id" => channel_id} = channel) do
    case DynamicSupervisor.start_child(__MODULE__, {CallSession, channel}) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("could not start call session for #{channel_id}: #{inspect(reason)}")
        error
    end
  end

  @doc "Number of calls currently running."
  def count_calls do
    %{active: active} = DynamicSupervisor.count_children(__MODULE__)
    active
  end
end
