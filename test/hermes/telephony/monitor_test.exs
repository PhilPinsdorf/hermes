defmodule Hermes.Telephony.MonitorTest do
  use ExUnit.Case, async: false

  import Mox
  import ExUnit.CaptureLog

  alias Hermes.Ari
  alias Hermes.Ari.ClientMock
  alias Hermes.Telephony.Monitor

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    previous = Ari.status()
    on_exit(fn -> Ari.put_status(previous) end)
    :ok
  end

  # A monitor of our own, so the application's one is left alone.
  defp start_monitor do
    start_supervised!({Monitor, [name: nil, check_on_start: false, interval: 60_000]},
      id: :test_monitor
    )
  end

  defp check(pid) do
    GenServer.call(pid, :check, 5_000)
  end

  test "reports ready when ARI and the trunk answer" do
    stub(ClientMock, :endpoint, fn "PJSIP/fritzbox" -> {:ok, %{"state" => "online"}} end)
    Ari.put_status(:connected)

    pid = start_monitor()
    assert %{ready?: true, ari: :connected, trunk: :online} = check(pid)
  end

  test "reports not ready and logs an error when the trunk is gone" do
    stub(ClientMock, :endpoint, fn _ -> {:ok, %{"state" => "offline"}} end)
    Ari.put_status(:connected)

    pid = start_monitor()

    log = capture_log(fn -> assert %{ready?: false, trunk: :offline} = check(pid) end)
    assert log =~ "telephony not ready"
  end

  test "does not ask for the trunk while ARI is down" do
    expect(ClientMock, :endpoint, 0, fn _ -> {:ok, %{"state" => "online"}} end)
    Ari.put_status(:disconnected)

    pid = start_monitor()
    assert %{ready?: false, ari: :disconnected, trunk: :unknown} = check(pid)
  end

  test "an ARI error counts as trunk offline" do
    stub(ClientMock, :endpoint, fn _ -> {:error, {:http, 404, "not found"}} end)
    Ari.put_status(:connected)

    pid = start_monitor()
    assert %{ready?: false, trunk: :offline} = check(pid)
  end

  test "announces a change only once and tells subscribers" do
    stub(ClientMock, :endpoint, fn _ -> {:ok, %{"state" => "online"}} end)
    Ari.put_status(:connected)
    Monitor.subscribe()

    pid = start_monitor()
    check(pid)
    assert_receive {:telephony_status, %{ready?: true}}

    check(pid)
    refute_receive {:telephony_status, _}, 50
  end
end
