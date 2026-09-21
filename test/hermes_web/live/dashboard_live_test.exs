defmodule HermesWeb.DashboardLiveTest do
  use HermesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hermes.DirectoryFixtures
  import Hermes.ScheduleFixtures

  setup :register_and_log_in_user

  test "requires login" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/")
  end

  test "shows open setup steps", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, ~s(#check-clip[data-done="false"]))
    assert has_element?(lv, ~s(#check-people[data-done="false"]))
  end

  test "ticks off steps as they are done", %{conn: conn} do
    {:ok, _} = Hermes.Settings.update(%{clip_number: "030 1234567"})
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, ~s(#check-clip[data-done="true"]))

    person_fixture()
    assert has_element?(lv, ~s(#check-people[data-done="true"]))
  end

  test "does not count inactive people", %{conn: conn} do
    person_fixture(active: false)
    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, ~s(#check-people[data-done="false"]))
  end

  describe "on duty" do
    test "warns when nobody is on duty", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      assert has_element?(lv, "#on-duty-none", "Anrufer hören die Ansage")
    end

    test "lists who is on duty right now, in call order", %{conn: conn} do
      local_now = Hermes.Schedule.local_naive(DateTime.utc_now())
      day = Date.day_of_week(local_now)
      anna = person_fixture(name: "Anna")
      bert = person_fixture(name: "Bert")
      # 24h shifts starting at 00:00 today cover "now" regardless of the clock
      shift_fixture(
        person_id: bert.id,
        day_of_week: day,
        starts_at: ~T[00:00:00],
        ends_at: ~T[00:00:00],
        position: 1
      )

      shift_fixture(
        person_id: anna.id,
        day_of_week: day,
        starts_at: ~T[00:00:00],
        ends_at: ~T[00:00:00],
        position: 0
      )

      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#on-duty-list li:first-child", "Anna")
      assert has_element?(lv, "#on-duty-list li:nth-child(2)", "Bert")
      assert has_element?(lv, "#next-change", "niemand")
    end

    test "updates when the plan changes", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      day = Date.day_of_week(Hermes.Schedule.local_naive(DateTime.utc_now()))
      person = person_fixture(name: "Neu")

      shift_fixture(
        person_id: person.id,
        day_of_week: day,
        starts_at: ~T[00:00:00],
        ends_at: ~T[00:00:00]
      )

      assert has_element?(lv, "#on-duty-list", "Neu")
    end

    test "hides the setup checklist once everything is set up", %{conn: conn} do
      {:ok, _} = Hermes.Settings.update(%{clip_number: "030 1234567"})
      shift_fixture()

      {:ok, lv, _html} = live(conn, ~p"/")
      refute has_element?(lv, "#setup-checklist")
    end
  end

  describe "PBX status" do
    setup do
      previous = Hermes.Ari.status()
      on_exit(fn -> Hermes.Ari.put_status(previous) end)
      :ok
    end

    test "shows when the line cannot be reached", %{conn: conn} do
      Hermes.Ari.put_status(:connected)
      {:ok, lv, _html} = live(conn, ~p"/")

      # Without a monitor check the trunk is unknown, which counts as not ready.
      assert has_element?(lv, "#trunk-status", "Amt nicht erreichbar")
      assert has_element?(lv, "#pbx-status", "Fritz!Box antwortet nicht")
    end

    test "reacts to the monitor reporting a change", %{conn: conn} do
      Hermes.Ari.put_status(:connected)
      {:ok, lv, _html} = live(conn, ~p"/")

      Phoenix.PubSub.broadcast(
        Hermes.PubSub,
        "telephony",
        {:telephony_status, %{ready?: true, ari: :connected, trunk: :online, since: nil}}
      )

      assert render(lv) =~ "Amt erreichbar"
    end

    test "shows when Asterisk is not connected", %{conn: conn} do
      Hermes.Ari.put_status(:disconnected)
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#pbx-status", "Telefonanlage getrennt")
      assert has_element?(lv, "#pbx-status", "nimmt Hermes keine Anrufe an")
    end

    test "updates live when the connection comes up", %{conn: conn} do
      Hermes.Ari.put_status(:disconnected)
      {:ok, lv, _html} = live(conn, ~p"/")

      Hermes.Ari.put_status(:connected)

      assert render_async_until(lv, "Telefonanlage verbunden")
    end
  end

  # The status arrives via PubSub, so the LiveView needs a moment to re-render.
  defp render_async_until(lv, text, attempts \\ 50) do
    cond do
      render(lv) =~ text -> true
      attempts == 0 -> flunk("#{text} did not appear")
      true -> Process.sleep(10) && render_async_until(lv, text, attempts - 1)
    end
  end
end
