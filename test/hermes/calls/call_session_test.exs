defmodule Hermes.Calls.CallSessionTest do
  @moduledoc """
  Every call path, driven against a mocked Asterisk: no PBX, no real timing.
  """
  use Hermes.DataCase, async: false

  import Mox
  import Hermes.DirectoryFixtures
  import Hermes.ScheduleFixtures

  alias Hermes.Ari.ClientMock
  alias Hermes.Calls
  alias Hermes.Calls.{CallSession, CallSupervisor, Log, Occupancy}
  alias Hermes.Directory.PhoneNumber
  alias Hermes.Settings
  alias Hermes.Sounds

  @caller_channel "caller-1"

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    stop_all_calls()
    on_exit(&stop_all_calls/0)

    # Short enough for tests, long enough not to fire between two steps.
    Application.put_env(:hermes, :confirm_timeout_seconds, 0.2)
    on_exit(fn -> Application.put_env(:hermes, :confirm_timeout_seconds, 20) end)

    {:ok, _} = Settings.update(%{clip_number: "030 1234567"})
    stub_asterisk()
    :ok
  end

  defp stop_all_calls do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(CallSupervisor), is_pid(pid) do
      ref = Process.monitor(pid)
      DynamicSupervisor.terminate_child(CallSupervisor, pid)

      receive do
        {:DOWN, ^ref, _, _, _} -> :ok
      after
        500 -> :ok
      end
    end

    :ok
  end

  # Records every ARI call as a message to the test process.
  defp stub_asterisk do
    test = self()

    stub(ClientMock, :ring, fn id -> send(test, {:ring, id}) && :ok end)
    stub(ClientMock, :ring_stop, fn id -> send(test, {:ring_stop, id}) && :ok end)
    stub(ClientMock, :answer, fn id -> send(test, {:answer, id}) && :ok end)

    stub(ClientMock, :play, fn id, media ->
      send(test, {:play, id, media})
      {:ok, "pb-" <> id}
    end)

    stub(ClientMock, :hangup, fn id -> send(test, {:hangup, id}) && :ok end)

    stub(ClientMock, :create_channel, fn endpoint, id, args ->
      send(test, {:create_channel, endpoint, id, args})
      {:ok, %{"id" => id}}
    end)

    stub(ClientMock, :set_variable, fn id, name, value ->
      send(test, {:set_variable, id, name, value})
      :ok
    end)

    stub(ClientMock, :dial, fn id, timeout -> send(test, {:dial, id, timeout}) && :ok end)

    stub(ClientMock, :create_bridge, fn id ->
      send(test, {:create_bridge, id})
      {:ok, %{"id" => id}}
    end)

    stub(ClientMock, :add_to_bridge, fn bridge_id, channels ->
      send(test, {:add_to_bridge, bridge_id, channels})
      :ok
    end)

    stub(ClientMock, :destroy_bridge, fn id -> send(test, {:destroy_bridge, id}) && :ok end)
  end

  ## helpers

  defp on_duty(people) do
    day = Date.day_of_week(Hermes.Schedule.local_naive(DateTime.utc_now()))

    people
    |> List.wrap()
    |> Enum.with_index()
    |> Enum.each(fn {person, index} ->
      shift_fixture(
        person_id: person.id,
        day_of_week: day,
        starts_at: ~T[00:00:00],
        ends_at: ~T[00:00:00],
        position: index
      )
    end)
  end

  defp start_call(channel_id \\ @caller_channel) do
    {:ok, pid} =
      CallSupervisor.start_call(%{
        "id" => channel_id,
        "caller" => %{"number" => "015112345678"}
      })

    {pid, Process.monitor(pid)}
  end

  # Waits for the session to have handled everything sent so far.
  defp sync(pid), do: CallSession.info(pid)

  defp event(pid, event) do
    Calls.handle_event(event)
    sync(pid)
  end

  defp leg_answered(pid, leg_id) do
    event(pid, %{"type" => "ChannelStateChange", "channel" => %{"id" => leg_id, "state" => "Up"}})
  end

  defp press(pid, leg_id, digit) do
    event(pid, %{
      "type" => "ChannelDtmfReceived",
      "channel" => %{"id" => leg_id},
      "digit" => digit
    })
  end

  defp leg_ended(pid, leg_id, cause) do
    event(pid, %{
      "type" => "ChannelDestroyed",
      "channel" => %{"id" => leg_id},
      "cause" => cause
    })
  end

  defp playback_finished(pid, channel_id) do
    event(pid, %{
      "type" => "PlaybackFinished",
      "playback" => %{"id" => "pb-" <> channel_id, "target_uri" => "channel:" <> channel_id}
    })
  end

  defp assert_dialed(person, caller_channel \\ @caller_channel) do
    assert_receive {:create_channel, endpoint, leg_id, ["outgoing", ^caller_channel]}
    assert endpoint == "PJSIP/" <> PhoneNumber.to_dialable(person.phone_e164) <> "@fritzbox"
    assert_receive {:dial, ^leg_id, _timeout}
    leg_id
  end

  ## tests

  describe "nobody to call" do
    test "plays the announcement when nobody is on duty" do
      {pid, _ref} = start_call()

      assert_receive {:answer, @caller_channel}
      assert_receive {:play, @caller_channel, media}
      assert media == Sounds.media(:no_one_on_duty)
      assert %{state: :announcing} = sync(pid)

      playback_finished(pid, @caller_channel)
      assert_receive {:hangup, @caller_channel}
    end

    test "plays the busy announcement when everybody on duty is in a call" do
      anna = person_fixture(name: "Anna")
      on_duty(anna)

      # Another call already holds Anna.
      holder = spawn_holder(fn -> Occupancy.acquire_person(anna.id) end)

      {_pid, _ref} = start_call()

      assert_receive {:play, @caller_channel, media}
      assert media == Sounds.media(:all_busy)
      refute_received {:create_channel, _, _, _}

      send(holder, :stop)
    end
  end

  describe "the global switch" do
    setup do
      anna = person_fixture(name: "Anna", phone_e164: "0171 1111111")
      on_duty(anna)
      %{anna: anna}
    end

    test "no phone rings while forwarding is switched off" do
      {:ok, _} = Settings.set_forwarding(false)

      {pid, _ref} = start_call()

      assert_receive {:play, @caller_channel, media}
      assert media == Sounds.media(:no_one_on_duty)
      refute_received {:create_channel, _, _, _}
      assert %{state: :announcing} = sync(pid)
    end

    test "the call log says the call arrived during a pause" do
      {:ok, _} = Settings.set_forwarding(false)

      {pid, ref} = start_call()
      assert_receive {:play, @caller_channel, _}

      GenServer.stop(pid, :normal)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}

      assert [%{result: :paused, attempts: []}] = Log.list_calls()
    end

    test "switching it on again makes the phone ring", %{anna: anna} do
      {:ok, _} = Settings.set_forwarding(false)
      {:ok, _} = Settings.set_forwarding(true)

      {_pid, _ref} = start_call()

      assert_dialed(anna)
    end
  end

  describe "forwarding" do
    setup do
      anna = person_fixture(name: "Anna", phone_e164: "0171 1111111")
      on_duty(anna)
      %{anna: anna}
    end

    test "rings the caller and calls the mobile", %{anna: anna} do
      {pid, _ref} = start_call()

      assert_receive {:ring, @caller_channel}
      assert_dialed(anna)

      # The Fritz!Box decides the caller id; overriding it would make the call
      # go out anonymously.
      refute_received {:set_variable, _, "CALLERID(num)", _}

      # The caller is not answered while we dial: no charges, no silence.
      refute_received {:answer, @caller_channel}
      assert %{state: :dialing} = sync(pid)
    end

    test "plays the confirmation only to the called person", %{anna: anna} do
      {pid, _ref} = start_call()
      leg = assert_dialed(anna)

      leg_answered(pid, leg)

      assert_receive {:play, ^leg, media}
      assert media == Sounds.media(:confirm)
      refute_received {:answer, @caller_channel}
      assert %{legs: %{^leg => :confirming}} = sync(pid)
    end

    test "key 1 bridges caller and mobile", %{anna: anna} do
      {pid, _ref} = start_call()
      leg = assert_dialed(anna)
      leg_answered(pid, leg)

      press(pid, leg, "1")

      assert_receive {:create_bridge, bridge_id}
      assert_receive {:ring_stop, @caller_channel}
      assert_receive {:answer, @caller_channel}
      assert_receive {:add_to_bridge, ^bridge_id, [@caller_channel, ^leg]}
      assert %{state: :bridged, attempts: attempts} = sync(pid)

      assert Enum.any?(
               attempts,
               &match?(%{person_id: id, outcome: :confirmed} when id == anna.id, &1)
             )
    end

    test "the person stays busy for other calls while bridged", %{anna: anna} do
      {pid, _ref} = start_call()
      leg = assert_dialed(anna)
      leg_answered(pid, leg)
      press(pid, leg, "1")

      assert Occupancy.busy_person_ids() == [anna.id]
      assert %{state: :bridged} = sync(pid)
    end

    test "a wrong key keeps the confirmation running", %{anna: anna} do
      {pid, _ref} = start_call()
      leg = assert_dialed(anna)
      leg_answered(pid, leg)

      press(pid, leg, "7")

      assert %{legs: %{^leg => :confirming}} = sync(pid)
      refute_received {:hangup, ^leg}
    end
  end

  describe "ring timeout" do
    test "the global default applies" do
      on_duty(person_fixture(phone_e164: "0171 3333333"))
      {_pid, _ref} = start_call()

      assert_receive {:dial, _leg_id, 25}
    end

    test "a person can override it" do
      on_duty(person_fixture(phone_e164: "0171 9999999", ring_timeout_seconds: 45))
      {_pid, _ref} = start_call()

      assert_receive {:dial, _leg_id, 45}
    end
  end

  describe "escalation" do
    setup do
      anna = person_fixture(name: "Anna", phone_e164: "0171 1111111")
      bert = person_fixture(name: "Bert", phone_e164: "0171 2222222")
      on_duty([anna, bert])
      %{anna: anna, bert: bert}
    end

    test "key 2 passes on to the next person right away", %{anna: anna, bert: bert} do
      {pid, _ref} = start_call()
      leg_a = assert_dialed(anna)
      leg_answered(pid, leg_a)

      press(pid, leg_a, "2")

      assert_receive {:hangup, ^leg_a}
      leg_b = assert_dialed(bert)
      assert %{legs: %{^leg_b => :dialing}} = sync(pid)
      assert Occupancy.busy_person_ids() == [bert.id]
    end

    test "a person who passed on is not called again", %{anna: anna, bert: bert} do
      {pid, _ref} = start_call()
      leg_a = assert_dialed(anna)
      leg_answered(pid, leg_a)
      press(pid, leg_a, "2")

      leg_b = assert_dialed(bert)
      leg_ended(pid, leg_b, 19)

      # Everybody has been tried: announcement instead of calling Anna again.
      assert_receive {:play, @caller_channel, media}
      assert media == Sounds.media(:no_one_on_duty)
      refute_received {:create_channel, _, _, _}
    end

    test "no key at all escalates after the timeout (voicemail case)", %{
      anna: anna,
      bert: bert
    } do
      {pid, _ref} = start_call()
      leg_a = assert_dialed(anna)
      leg_answered(pid, leg_a)

      # The mailbox picked up but never presses a key.
      assert_receive {:hangup, ^leg_a}, 1_000
      assert_dialed(bert)
      assert %{attempts: attempts} = sync(pid)

      assert Enum.any?(
               attempts,
               &match?(%{person_id: id, outcome: :no_confirmation} when id == anna.id, &1)
             )
    end

    test "a busy mobile escalates immediately", %{anna: anna, bert: bert} do
      {pid, _ref} = start_call()
      leg_a = assert_dialed(anna)

      leg_ended(pid, leg_a, 17)

      assert_dialed(bert)
      assert %{attempts: attempts} = sync(pid)
      assert Enum.any?(attempts, &match?(%{person_id: id, outcome: :busy} when id == anna.id, &1))
    end

    test "after everyone was tried the caller gets the announcement", %{
      anna: anna,
      bert: bert
    } do
      {pid, _ref} = start_call()
      leg_a = assert_dialed(anna)
      leg_ended(pid, leg_a, 19)
      leg_b = assert_dialed(bert)
      leg_ended(pid, leg_b, 19)

      assert_receive {:answer, @caller_channel}
      assert_receive {:play, @caller_channel, media}
      assert media == Sounds.media(:no_one_on_duty)
      assert Occupancy.busy_person_ids() == []
    end
  end

  describe "key 3 (reject for everyone)" do
    setup do
      anna = person_fixture(name: "Anna", phone_e164: "0171 1111111")
      bert = person_fixture(name: "Bert", phone_e164: "0171 2222222")
      on_duty([anna, bert])
      %{anna: anna, bert: bert}
    end

    test "ends the call although somebody else was left", %{anna: anna} do
      {pid, _ref} = start_call()
      leg_a = assert_dialed(anna)
      leg_answered(pid, leg_a)

      press(pid, leg_a, "3")

      assert_receive {:hangup, ^leg_a}
      assert_receive {:play, @caller_channel, media}
      assert media == Sounds.media(:no_one_on_duty)
      refute_received {:create_channel, _, _, _}

      assert %{state: :announcing, queue: [], attempts: attempts} = sync(pid)

      assert Enum.any?(
               attempts,
               &match?(%{person_id: id, outcome: :rejected_all} when id == anna.id, &1)
             )

      playback_finished(pid, @caller_channel)
      assert_receive {:hangup, @caller_channel}
    end

    test "frees the people again", %{anna: anna} do
      {pid, _ref} = start_call()
      leg_a = assert_dialed(anna)
      leg_answered(pid, leg_a)
      press(pid, leg_a, "3")

      assert Occupancy.busy_person_ids() == []
    end
  end

  describe "ring strategy" do
    setup do
      anna = person_fixture(name: "Anna", phone_e164: "0171 1111111")
      bert = person_fixture(name: "Bert", phone_e164: "0171 2222222")
      on_duty([anna, bert])
      %{anna: anna, bert: bert}
    end

    test "simultaneous rings both when the line has enough channels", %{
      anna: anna,
      bert: bert
    } do
      {:ok, _} = Settings.update(%{ring_strategy: :simultaneous, max_external_channels: 4})

      {pid, _ref} = start_call()

      leg_a = assert_dialed(anna)
      leg_b = assert_dialed(bert)
      assert %{legs: legs} = sync(pid)
      assert map_size(legs) == 2
      assert Enum.sort(Occupancy.busy_person_ids()) == Enum.sort([anna.id, bert.id])

      # Whoever presses 1 first wins; the other leg is cancelled.
      leg_answered(pid, leg_b)
      press(pid, leg_b, "1")

      assert_receive {:hangup, ^leg_a}
      assert %{state: :bridged, legs: %{^leg_b => :bridged}} = sync(pid)
    end

    test "simultaneous degrades to sequential on a two-channel line", %{anna: anna} do
      {:ok, _} = Settings.update(%{ring_strategy: :simultaneous, max_external_channels: 2})

      {pid, _ref} = start_call()

      assert_dialed(anna)
      assert %{legs: legs} = sync(pid)
      assert map_size(legs) == 1
    end
  end

  describe "several calls at the same time" do
    setup do
      anna = person_fixture(name: "Anna", phone_e164: "0171 1111111")
      bert = person_fixture(name: "Bert", phone_e164: "0171 2222222")
      on_duty([anna, bert])
      {:ok, _} = Settings.update(%{max_external_channels: 8})
      %{anna: anna, bert: bert}
    end

    test "the second call gets the second person", %{anna: anna, bert: bert} do
      {_first, _} = start_call("caller-1")
      assert_dialed(anna, "caller-1")

      {_second, _} = start_call("caller-2")
      assert_dialed(bert, "caller-2")

      assert Enum.sort(Occupancy.busy_person_ids()) == Enum.sort([anna.id, bert.id])
    end

    test "when everybody is busy the next caller hears the busy announcement", %{
      anna: anna,
      bert: bert
    } do
      {_first, _} = start_call("caller-1")
      assert_dialed(anna, "caller-1")
      {_second, _} = start_call("caller-2")
      assert_dialed(bert, "caller-2")

      {_third, _} = start_call("caller-3")

      assert_receive {:play, "caller-3", media}
      assert media == Sounds.media(:all_busy)
    end

    test "a crashed session frees its people and channels", %{anna: anna} do
      {pid, ref} = start_call("caller-1")
      assert_dialed(anna, "caller-1")
      assert Occupancy.busy_person_ids() == [anna.id]

      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      wait_until(fn -> Occupancy.busy_person_ids() == [] end)
      wait_until(fn -> Occupancy.used_channels() == 0 end)
    end
  end

  describe "the caller hangs up" do
    setup do
      anna = person_fixture(name: "Anna", phone_e164: "0171 1111111")
      on_duty(anna)
      %{anna: anna}
    end

    test "while we are dialing: the mobile stops ringing", %{anna: anna} do
      {pid, ref} = start_call()
      leg = assert_dialed(anna)

      Calls.handle_event(%{
        "type" => "ChannelDestroyed",
        "channel" => %{"id" => @caller_channel},
        "cause" => 16
      })

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert_receive {:hangup, ^leg}
      wait_until(fn -> Occupancy.busy_person_ids() == [] end)
    end

    test "while bridged: the other side is hung up too", %{anna: anna} do
      {pid, ref} = start_call()
      leg = assert_dialed(anna)
      leg_answered(pid, leg)
      press(pid, leg, "1")
      assert_receive {:create_bridge, bridge_id}

      # Now the called person hangs up.
      Calls.handle_event(%{
        "type" => "ChannelDestroyed",
        "channel" => %{"id" => leg},
        "cause" => 16
      })

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert_receive {:hangup, @caller_channel}
      assert_receive {:destroy_bridge, ^bridge_id}
    end
  end

  describe "call log" do
    setup do
      anna = person_fixture(name: "Anna", phone_e164: "0171 1111111")
      bert = person_fixture(name: "Bert", phone_e164: "0171 2222222")
      on_duty([anna, bert])
      %{anna: anna, bert: bert}
    end

    defp logged_call(pid, ref) do
      GenServer.stop(pid, :normal)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}
      [call] = Log.list_calls()
      Log.get_call!(call.id)
    end

    test "a call that was put through", %{anna: anna} do
      {pid, ref} = start_call()
      leg = assert_dialed(anna)
      leg_answered(pid, leg)
      press(pid, leg, "1")

      call = logged_call(pid, ref)

      assert call.result == :bridged
      assert call.channel_id == @caller_channel
      assert call.caller_number == "015112345678"
      assert call.person_id == anna.id
      assert call.talk_seconds >= 0
      assert [%{person_name: "Anna", outcome: :confirmed, position: 1}] = call.attempts
    end

    test "an escalation with the reason per attempt", %{anna: anna, bert: bert} do
      {pid, ref} = start_call()
      leg_a = assert_dialed(anna)
      leg_ended(pid, leg_a, 17)
      leg_b = assert_dialed(bert)
      leg_answered(pid, leg_b)
      press(pid, leg_b, "2")

      call = logged_call(pid, ref)

      assert call.result == :announced
      assert call.person_id == nil

      assert Enum.map(call.attempts, &{&1.person_name, &1.outcome}) == [
               {"Anna", :busy},
               {"Bert", :passed}
             ]
    end

    test "a call rejected with key 3", %{anna: anna} do
      {pid, ref} = start_call()
      leg = assert_dialed(anna)
      leg_answered(pid, leg)
      press(pid, leg, "3")

      assert %{result: :rejected} = logged_call(pid, ref)
    end

    test "nobody on duty" do
      Hermes.Repo.delete_all(Hermes.Schedule.Shift)

      {pid, ref} = start_call("caller-empty")
      assert_receive {:play, "caller-empty", _}

      call = logged_call(pid, ref)
      assert call.result == :announced
      assert call.attempts == []
    end

    test "the caller hung up while we were dialing", %{anna: anna} do
      {pid, ref} = start_call()
      assert_dialed(anna)

      Calls.handle_event(%{
        "type" => "ChannelDestroyed",
        "channel" => %{"id" => @caller_channel},
        "cause" => 16
      })

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      [call] = Log.list_calls()
      assert call.result == :abandoned
    end
  end

  ## small helpers

  defp spawn_holder(fun) do
    test = self()

    pid =
      spawn(fn ->
        fun.()
        send(test, :holding)

        receive do
          :stop -> :ok
        end
      end)

    receive do
      :holding -> :ok
    after
      1_000 -> flunk("holder did not start")
    end

    pid
  end

  defp wait_until(fun, attempts \\ 50) do
    cond do
      fun.() -> :ok
      attempts == 0 -> flunk("condition never became true")
      true -> Process.sleep(10) && wait_until(fun, attempts - 1)
    end
  end
end
