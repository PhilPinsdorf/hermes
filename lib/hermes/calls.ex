defmodule Hermes.Calls do
  @moduledoc """
  Entry point for everything Asterisk reports about calls.

  Every call gets its own `Hermes.Calls.CallSession` process, registered under
  the channel id of the caller. Events are routed to that process; a crashing
  session can therefore never take other calls with it.
  """

  require Logger

  alias Hermes.Calls.{CallSession, CallSupervisor}

  @registry Hermes.Calls.Registry
  @topic "calls"

  @doc """
  Subscribes to `{:call_started, channel_id}` / `{:call_ended, channel_id}`.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Hermes.PubSub, @topic)
  end

  @doc false
  def broadcast(message) do
    Phoenix.PubSub.broadcast(Hermes.PubSub, @topic, message)
  end

  @doc """
  Handles one ARI event: starts a session for a new call, routes everything
  else to the session of that channel.
  """
  def handle_event(%{"type" => "StasisStart", "channel" => channel} = event) do
    # A channel Hermes created itself (an outgoing leg) carries our own
    # arguments; only real incoming calls start a session.
    case event["args"] do
      args when args in [nil, []] -> CallSupervisor.start_call(channel)
      _ -> :ok
    end
  end

  def handle_event(%{"type" => type} = event) do
    case channel_id(event) do
      nil ->
        :ok

      channel_id ->
        case Registry.lookup(@registry, channel_id) do
          [{pid, _}] -> CallSession.handle_event(pid, type, event)
          [] -> :ok
        end
    end
  end

  def handle_event(_event), do: :ok

  @doc "The registry name sessions register in."
  def registry, do: @registry

  @doc "Looks up the session of a channel."
  def whereis(channel_id) do
    case Registry.lookup(@registry, channel_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Channel ids of all running calls."
  def list_channel_ids do
    Registry.select(@registry, [{{:"$1", :_, :"$2"}, [{:"/=", :"$2", :leg}], [:"$1"]}])
  end

  @doc """
  What is going on right now: one entry per running call. Sessions that end
  while we ask are simply left out.
  """
  def running do
    @registry
    |> Registry.select([{{:_, :"$1", :"$2"}, [{:"/=", :"$2", :leg}], [:"$1"]}])
    |> Enum.flat_map(fn pid ->
      try do
        [CallSession.info(pid)]
      catch
        :exit, _ -> []
      end
    end)
    |> Enum.sort_by(& &1.started_at, DateTime)
  end

  defp channel_id(%{"channel" => %{"id" => id}}), do: id
  defp channel_id(%{"playback" => %{"target_uri" => "channel:" <> id}}), do: id
  defp channel_id(_event), do: nil
end
