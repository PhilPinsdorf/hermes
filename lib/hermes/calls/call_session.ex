defmodule Hermes.Calls.CallSession do
  @moduledoc """
  One process per incoming call, driving it through its states:

      :starting → :resolving → :dialing ⇄ :confirming → :bridged → :done
                            ↘ :announcing ↗

  What the called person hears and can do (see `Hermes.Sounds`, key `:confirm`):

    * **1** — accept: caller and mobile phone are bridged
    * **2** — pass on: this leg hangs up, the next person is called right away
    * **3** — reject: every ringing leg is cancelled, the caller gets the
      announcement and the call ends
    * no key / any other key: after the confirmation timeout the leg is
      dropped like a **2** — this is what catches a voicemail box picking up

  Privacy: the caller's channel is *not* answered while we dial and while the
  confirmation runs; they only hear ringback (`ring`). They are answered right
  before bridging, or to hear an announcement. Both channels meet in a mixing
  bridge, so the caller never learns the mobile number.
  """
  use GenServer, restart: :temporary

  require Logger

  alias Hermes.Ari
  alias Hermes.Calls
  alias Hermes.Calls.{Log, Occupancy, Strategy}
  alias Hermes.Schedule
  alias Hermes.Settings
  alias Hermes.Sounds
  alias Hermes.Telephony

  defstruct [
    :channel_id,
    :caller,
    :state,
    :settings,
    :bridge_id,
    :inbound_slot,
    :started_at,
    # set once the call was put through
    :bridged_at,
    :bridged_person_id,
    # which announcement the caller heard, if any
    :announced_with,
    # set when the call arrived while forwarding was switched off
    paused?: false,
    # people still to try, in call order
    queue: [],
    # outgoing legs: channel_id => %{person:, state:, slot:, timer:}
    legs: %{},
    # people who will not be tried again in this call
    declined: MapSet.new(),
    # what happened per attempt, for the call log in M6
    attempts: []
  ]

  @doc false
  def child_spec(channel) do
    %{
      id: {__MODULE__, channel["id"]},
      start: {__MODULE__, :start_link, [channel]},
      restart: :temporary
    }
  end

  def start_link(%{"id" => channel_id} = channel) do
    GenServer.start_link(__MODULE__, channel, name: via(channel_id))
  end

  defp via(channel_id), do: {:via, Registry, {Calls.registry(), channel_id}}

  @doc "Hands an ARI event to the session of this call."
  def handle_event(pid, type, event), do: GenServer.cast(pid, {:ari_event, type, event})

  @doc "Current state of the call (for tests and the live view)."
  def info(pid), do: GenServer.call(pid, :info)

  @impl true
  def init(channel) do
    state = %__MODULE__{
      channel_id: channel["id"],
      caller: get_in(channel, ["caller", "number"]),
      state: :starting,
      settings: Settings.get(),
      started_at: DateTime.utc_now()
    }

    Calls.broadcast({:call_started, state.channel_id})
    {:ok, state, {:continue, :resolve}}
  end

  @impl true
  def handle_continue(:resolve, state) do
    busy = MapSet.new(Occupancy.busy_person_ids())
    # call_order, not status: ties are rolled per call, and the next change is
    # of no interest here.
    on_duty = Schedule.call_order()
    available = Enum.reject(on_duty, &MapSet.member?(busy, &1.id))

    # The caller's own channel occupies one of the line's channels.
    state = %{state | inbound_slot: take_channel_slot()}

    cond do
      not state.settings.forwarding_enabled ->
        Logger.info("call #{state.channel_id}: forwarding is switched off")
        {:noreply, announce(%{state | state: :resolving, paused?: true}, :no_one_on_duty)}

      on_duty == [] ->
        Logger.info("call #{state.channel_id}: nobody on duty")
        {:noreply, announce(%{state | state: :resolving}, :no_one_on_duty)}

      available == [] ->
        Logger.info("call #{state.channel_id}: everybody on duty is busy")
        {:noreply, announce(%{state | state: :resolving}, :all_busy)}

      true ->
        Logger.info(
          "call #{state.channel_id}: calling #{Enum.map_join(available, ", ", & &1.name)}"
        )

        Ari.ring(state.channel_id)
        {:noreply, dial_next(%{state | state: :dialing, queue: available})}
    end
  end

  ## ARI events

  @impl true
  def handle_cast({:ari_event, type, event}, state) do
    {:noreply, on_event(type, event, state)}
  end

  @impl true
  def handle_call(:info, _from, state) do
    reply =
      state
      |> Map.take([:channel_id, :caller, :state, :started_at, :attempts])
      |> Map.put(:queue, Enum.map(state.queue, & &1.id))
      |> Map.put(:legs, Map.new(state.legs, fn {id, leg} -> {id, leg.state} end))
      |> Map.put(:leg_people, Enum.map(state.legs, fn {_, leg} -> leg.person.id end))

    {:reply, reply, state}
  end

  @impl true
  def handle_info({:confirm_timeout, leg_id}, state) do
    case state.legs[leg_id] do
      %{state: :confirming} = leg ->
        Logger.info("call #{state.channel_id}: #{leg.person.name} did not press a key")
        {:noreply, drop_leg(state, leg_id, :no_confirmation)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(:end_call, state), do: {:stop, :normal, state}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.legs, fn {leg_id, _leg} -> Ari.hangup(leg_id) end)
    # Nobody may be left in a half-empty bridge; hanging up a gone channel is a no-op.
    Ari.hangup(state.channel_id)
    if state.bridge_id, do: Ari.destroy_bridge(state.bridge_id)
    write_log(state)
    Calls.broadcast({:call_ended, state.channel_id})
    :ok
  end

  # What is left of the call: one line in the call log, plus one row per attempt.
  defp write_log(state) do
    ended_at = DateTime.utc_now()

    attrs = %{
      channel_id: state.channel_id,
      caller_number: state.caller,
      started_at: DateTime.truncate(state.started_at, :second),
      ended_at: DateTime.truncate(ended_at, :second),
      total_seconds: DateTime.diff(ended_at, state.started_at),
      talk_seconds: state.bridged_at && DateTime.diff(ended_at, state.bridged_at),
      result: result_of(state),
      person_id: state.bridged_person_id,
      attempts: state.attempts
    }

    case Log.record(attrs) do
      {:ok, _call_log} ->
        :ok

      {:error, changeset} ->
        Logger.error(
          "call #{state.channel_id}: could not write the call log: #{inspect(changeset.errors)}"
        )
    end
  end

  defp result_of(%{bridged_at: %DateTime{}}), do: :bridged

  defp result_of(state) do
    cond do
      state.paused? -> :paused
      Enum.any?(state.attempts, &(&1.outcome == :rejected_all)) -> :rejected
      state.announced_with == :all_busy -> :all_busy
      state.announced_with != nil -> :announced
      state.state == :done and state.attempts == [] -> :abandoned
      state.state in [:dialing, :confirming, :starting, :resolving] -> :abandoned
      true -> :failed
    end
  end

  # ------------------------------------------------------------------
  # events

  # The called phone picked up: play the confirmation to that leg only.
  defp on_event("ChannelStateChange", %{"channel" => %{"id" => id, "state" => "Up"}}, state) do
    case state.legs[id] do
      %{state: :dialing} = leg ->
        Logger.info("call #{state.channel_id}: #{leg.person.name} picked up, asking for a key")
        start_confirmation(state, id)

      _ ->
        state
    end
  end

  defp on_event("ChannelDtmfReceived", %{"channel" => %{"id" => id}, "digit" => digit}, state) do
    case state.legs[id] do
      %{state: :confirming} = leg -> on_digit(digit, state, id, leg)
      _ -> state
    end
  end

  # A leg ended: busy, rejected on the phone, or the dial timeout ran out.
  defp on_event(type, %{"channel" => %{"id" => id}} = event, state)
       when type in ["ChannelDestroyed", "StasisEnd"] do
    cond do
      Map.has_key?(state.legs, id) and state.state == :bridged ->
        Logger.info("call #{state.channel_id}: the called person hung up")
        stop_call(state)

      Map.has_key?(state.legs, id) ->
        outcome = leg_outcome(event)
        Logger.info("call #{state.channel_id}: leg ended (#{outcome})")
        drop_leg(state, id, outcome)

      id == state.channel_id ->
        Logger.info("call #{state.channel_id}: caller hung up")
        stop_call(state)

      true ->
        state
    end
  end

  defp on_event("ChannelHangupRequest", %{"channel" => %{"id" => id}}, state)
       when is_binary(id) do
    if id == state.channel_id, do: stop_call(state), else: state
  end

  defp on_event("PlaybackFinished", event, %{state: :announcing} = state) do
    if playback_target(event) == state.channel_id do
      Ari.hangup(state.channel_id)
      stop_call(%{state | state: :done})
    else
      state
    end
  end

  defp on_event(_type, _event, state), do: state

  # Asterisk reports the ISDN cause of a leg that ended.
  defp leg_outcome(%{"cause" => 17}), do: :busy
  defp leg_outcome(%{"cause" => cause}) when cause in [18, 19], do: :no_answer
  defp leg_outcome(%{"cause" => 21}), do: :rejected
  defp leg_outcome(_event), do: :no_answer

  ## keys

  defp on_digit("1", state, leg_id, leg) do
    Logger.info("call #{state.channel_id}: #{leg.person.name} accepted the call")
    connect(state, leg_id, leg)
  end

  defp on_digit("2", state, leg_id, leg) do
    Logger.info("call #{state.channel_id}: #{leg.person.name} passed the call on")
    drop_leg(state, leg_id, :passed)
  end

  defp on_digit("3", state, _leg_id, leg) do
    Logger.info("call #{state.channel_id}: #{leg.person.name} rejected the call for everyone")

    state
    |> record(leg.person, :rejected_all)
    |> cancel_all_legs()
    |> Map.put(:queue, [])
    |> announce(:no_one_on_duty)
  end

  # Mis-press: keep waiting, the person can still press the right key.
  defp on_digit(_digit, state, _leg_id, _leg), do: state

  # ------------------------------------------------------------------
  # dialing

  defp dial_next(%{queue: []} = state) do
    if map_size(state.legs) == 0 do
      # everyone has been tried and nothing is ringing any more
      announce(state, :no_one_on_duty)
    else
      state
    end
  end

  defp dial_next(state) do
    free = free_channels()
    legs = Strategy.legs_to_dial(state.settings.ring_strategy, free, length(state.queue))

    cond do
      legs > 0 ->
        {people, rest} = Enum.split(state.queue, legs)
        Enum.reduce(people, %{state | queue: rest}, &dial_person(&2, &1))

      map_size(state.legs) > 0 ->
        # no free channel right now, but something is still ringing
        state

      true ->
        Logger.warning("call #{state.channel_id}: no free channel to call out")
        announce(state, :all_busy)
    end
  end

  defp dial_person(state, person) do
    case Occupancy.acquire_person(person.id) do
      {:error, :busy} ->
        Logger.info("call #{state.channel_id}: #{person.name} is busy, skipping")
        state |> record(person, :busy) |> decline(person) |> dial_next()

      :ok ->
        dial_acquired_person(state, person)
    end
  end

  defp dial_acquired_person(state, person) do
    case Occupancy.acquire_channel(Telephony.max_concurrent_legs()) do
      {:error, :no_channel} ->
        Occupancy.release_person(person.id)
        Logger.warning("call #{state.channel_id}: no free channel for #{person.name}")
        %{state | queue: [person | state.queue]}

      {:ok, slot} ->
        leg_id = Ecto.UUID.generate()
        # Register before dialing: Asterisk may report events for this channel
        # immediately, and an event without a session would be lost.
        Registry.register(Calls.registry(), leg_id, :leg)

        case create_leg(leg_id, person, state) do
          :ok ->
            leg = %{person: person, state: :dialing, slot: slot, timer: nil}
            %{state | legs: Map.put(state.legs, leg_id, leg)}

          {:error, reason} ->
            Registry.unregister(Calls.registry(), leg_id)
            Occupancy.release_person(person.id)
            Occupancy.release_channel(slot)

            Logger.warning(
              "call #{state.channel_id}: could not call #{person.name}: #{inspect(reason)}"
            )

            state |> record(person, :failed) |> decline(person) |> dial_next()
        end
    end
  end

  defp create_leg(leg_id, person, state) do
    endpoint = Telephony.endpoint_for(person.phone_e164)
    timeout = person.ring_timeout_seconds || state.settings.ring_timeout_seconds

    with {:ok, _channel} <- Ari.create_channel(endpoint, leg_id, ["outgoing", state.channel_id]),
         :ok <- set_caller_id(leg_id) do
      Ari.dial(leg_id, timeout)
    end
  end

  # The called phone must never see the caller's number, only the configured one.
  defp set_caller_id(leg_id) do
    case Telephony.caller_id() do
      nil -> :ok
      number -> Ari.set_variable(leg_id, "CALLERID(num)", number)
    end
  end

  defp start_confirmation(state, leg_id) do
    case Ari.play(leg_id, Sounds.media(:confirm)) do
      {:ok, _playback_id} ->
        timer = Process.send_after(self(), {:confirm_timeout, leg_id}, confirm_timeout())
        update_leg(state, leg_id, &%{&1 | state: :confirming, timer: timer})

      {:error, reason} ->
        Logger.warning("call #{state.channel_id}: confirmation failed: #{inspect(reason)}")
        drop_leg(state, leg_id, :failed)
    end
  end

  # Put caller and called person together. Everything else that is ringing is
  # cancelled: whoever pressed 1 first wins.
  defp connect(state, leg_id, leg) do
    bridge_id = Ecto.UUID.generate()
    state = state |> cancel_other_legs(leg_id) |> record(leg.person, :confirmed)

    Ari.ring_stop(state.channel_id)

    with {:ok, _bridge} <- Ari.create_bridge(bridge_id),
         :ok <- Ari.answer(state.channel_id),
         :ok <- Ari.add_to_bridge(bridge_id, [state.channel_id, leg_id]) do
      Calls.broadcast({:call_bridged, state.channel_id})

      state
      |> Map.put(:bridge_id, bridge_id)
      |> Map.put(:state, :bridged)
      |> Map.put(:bridged_at, DateTime.utc_now())
      |> Map.put(:bridged_person_id, leg.person.id)
      |> update_leg(leg_id, &%{&1 | state: :bridged})
    else
      {:error, reason} ->
        Logger.error("call #{state.channel_id}: bridging failed: #{inspect(reason)}")
        Ari.hangup(leg_id)
        announce(%{state | legs: Map.delete(state.legs, leg_id)}, :no_one_on_duty)
    end
  end

  # ------------------------------------------------------------------
  # legs

  defp drop_leg(state, leg_id, outcome) do
    case state.legs[leg_id] do
      nil ->
        state

      leg ->
        cancel_timer(leg)
        Ari.hangup(leg_id)
        release_leg(leg)
        Registry.unregister(Calls.registry(), leg_id)

        state
        |> record(leg.person, outcome)
        |> decline(leg.person)
        |> Map.put(:legs, Map.delete(state.legs, leg_id))
        |> dial_next()
    end
  end

  defp cancel_other_legs(state, keep_id) do
    Enum.reduce(state.legs, state, fn
      {^keep_id, _leg}, acc ->
        acc

      {leg_id, leg}, acc ->
        cancel_timer(leg)
        Ari.hangup(leg_id)
        release_leg(leg)
        Registry.unregister(Calls.registry(), leg_id)
        %{acc | legs: Map.delete(acc.legs, leg_id)}
    end)
  end

  defp cancel_all_legs(state), do: cancel_other_legs(state, nil)

  defp release_leg(leg) do
    Occupancy.release_person(leg.person.id)
    if leg[:slot], do: Occupancy.release_channel(leg.slot)
  end

  defp cancel_timer(%{timer: timer}) when is_reference(timer), do: Process.cancel_timer(timer)
  defp cancel_timer(_leg), do: :ok

  defp update_leg(state, leg_id, fun) do
    case state.legs[leg_id] do
      nil -> state
      leg -> %{state | legs: Map.put(state.legs, leg_id, fun.(leg))}
    end
  end

  defp decline(state, person), do: %{state | declined: MapSet.put(state.declined, person.id)}

  defp record(state, person, outcome) do
    attempt = %{person_id: person.id, person_name: person.name, outcome: outcome}
    %{state | attempts: state.attempts ++ [attempt]}
  end

  # ------------------------------------------------------------------
  # announcements and ending

  defp announce(state, sound) when is_atom(sound) do
    Ari.ring_stop(state.channel_id)

    with :ok <- Ari.answer(state.channel_id),
         {:ok, _playback_id} <- Ari.play(state.channel_id, announcement_media(sound, state)) do
      %{state | state: :announcing, announced_with: sound}
    else
      {:error, reason} ->
        Logger.warning("call #{state.channel_id}: announcement failed: #{inspect(reason)}")
        Ari.hangup(state.channel_id)
        %{state | state: :done}
    end
  end

  # The call is over; stop after this event has been handled.
  # "Nobody on duty" may also name when somebody is back.
  defp announcement_media(:no_one_on_duty, state) do
    Sounds.no_one_on_duty_media(Schedule.status().next_change, state.settings)
  end

  defp announcement_media(sound, _state), do: Sounds.media(sound)

  defp stop_call(state) do
    send(self(), :end_call)
    %{state | state: :done}
  end

  defp take_channel_slot do
    case Occupancy.acquire_channel(Telephony.max_concurrent_legs()) do
      {:ok, slot} -> slot
      {:error, :no_channel} -> nil
    end
  end

  defp free_channels do
    max(Telephony.max_concurrent_legs() - Occupancy.used_channels(), 0)
  end

  defp confirm_timeout do
    trunc(Application.get_env(:hermes, :confirm_timeout_seconds, 20) * 1000)
  end

  defp playback_target(%{"playback" => %{"target_uri" => "channel:" <> id}}), do: id
  defp playback_target(_event), do: nil
end
