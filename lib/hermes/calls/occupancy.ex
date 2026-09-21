defmodule Hermes.Calls.Occupancy do
  @moduledoc """
  Who and what is currently busy — atomically, without a lock table.

  Everything is a unique key in one `Registry`:

    * `{:person, id}` — this person is in a call of this system right now
    * `{:channel_slot, 1..N}` — one of the line's concurrent external calls

  Registering is atomic, so two calls arriving at the same moment can never
  grab the same person or the same channel. Whoever holds the entry is the
  `CallSession` process; when it dies, the registry frees the entries by
  itself — no cleanup job, no stuck reservations.
  """

  @registry __MODULE__

  @doc false
  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: @registry)
  end

  @doc "Registry name (also used by tests)."
  def registry, do: @registry

  @doc """
  Marks a person as busy for the calling process.
  """
  @spec acquire_person(integer()) :: :ok | {:error, :busy}
  def acquire_person(person_id) do
    case Registry.register(@registry, {:person, person_id}, nil) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _pid}} -> {:error, :busy}
    end
  end

  @doc "Frees a person again (e.g. they did not pick up)."
  @spec release_person(integer()) :: :ok
  def release_person(person_id), do: Registry.unregister(@registry, {:person, person_id})

  @doc "Ids of all people currently in a call."
  @spec busy_person_ids() :: [integer()]
  def busy_person_ids do
    Registry.select(@registry, [
      {{{:person, :"$1"}, :_, :_}, [], [:"$1"]}
    ])
  end

  @doc """
  Takes one of the `max` channel slots of the line. Slots are tried in order,
  so the first free number wins.
  """
  @spec acquire_channel(pos_integer()) :: {:ok, pos_integer()} | {:error, :no_channel}
  def acquire_channel(max) when max > 0 do
    Enum.find_value(1..max, {:error, :no_channel}, fn slot ->
      case Registry.register(@registry, {:channel_slot, slot}, nil) do
        {:ok, _} -> {:ok, slot}
        {:error, {:already_registered, _pid}} -> nil
      end
    end)
  end

  @doc "Frees a channel slot."
  @spec release_channel(pos_integer()) :: :ok
  def release_channel(slot), do: Registry.unregister(@registry, {:channel_slot, slot})

  @doc "How many channels of the line are in use."
  @spec used_channels() :: non_neg_integer()
  def used_channels do
    @registry
    |> Registry.select([{{{:channel_slot, :"$1"}, :_, :_}, [], [:"$1"]}])
    |> length()
  end
end
