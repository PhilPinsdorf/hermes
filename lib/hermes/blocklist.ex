defmodule Hermes.Blocklist do
  @moduledoc """
  Numbers that never reach anybody's phone.

  A call from a blocked number is answered with an announcement and ends
  there — no shift is looked up, no mobile rings. That is the difference to
  switching forwarding off, which affects everyone.

  Numbers are compared in E.164. Asterisk reports a caller the way the
  Fritz!Box hands it over — usually national (`015112345678`) — so everything
  that goes in or out of here is normalized first. Whatever cannot be
  normalized (a withheld number, an already anonymized log entry) is simply
  not blocked.
  """

  import Ecto.Query, warn: false

  alias Hermes.Blocklist.BlockedNumber
  alias Hermes.Directory.PhoneNumber
  alias Hermes.Repo

  @topic "blocklist"

  @doc "Subscribes the caller to `{:blocklist_changed, _}` messages."
  def subscribe, do: Phoenix.PubSub.subscribe(Hermes.PubSub, @topic)

  @doc "All blocked numbers, newest first."
  def list do
    Repo.all(from b in BlockedNumber, order_by: [desc: b.inserted_at, desc: b.id])
  end

  @doc """
  The blocked numbers as a set of E.164 strings — for checking a whole list of
  calls without one query per row.
  """
  def numbers do
    BlockedNumber
    |> select([b], b.number)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Whether calls from `number` are blocked. Accepts any notation, and `nil`.
  """
  def blocked?(number, blocked \\ nil) do
    case PhoneNumber.normalize(number, allow_internal: true) do
      {:ok, e164} -> e164 in (blocked || numbers())
      {:error, _reason} -> false
    end
  end

  @doc "Blocks a number. `attrs` are `:number` and an optional `:note`."
  def block(attrs) do
    %BlockedNumber{}
    |> BlockedNumber.changeset(attrs)
    |> Repo.insert()
    |> broadcast()
  end

  @doc "Lets a number through again."
  def unblock(%BlockedNumber{} = blocked_number) do
    blocked_number
    |> Repo.delete()
    |> broadcast()
  end

  def get!(id), do: Repo.get!(BlockedNumber, id)

  def change(%BlockedNumber{} = blocked_number, attrs \\ %{}) do
    BlockedNumber.changeset(blocked_number, attrs)
  end

  defp broadcast({:ok, blocked_number} = result) do
    Phoenix.PubSub.broadcast(Hermes.PubSub, @topic, {:blocklist_changed, blocked_number})
    result
  end

  defp broadcast(error), do: error
end
