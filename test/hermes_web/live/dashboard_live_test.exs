defmodule HermesWeb.DashboardLiveTest do
  use HermesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Hermes.DirectoryFixtures
  import Hermes.ScheduleFixtures

  alias Hermes.Calls.Log
  alias Hermes.Settings

  setup :register_and_log_in_user

  setup do
    previous = Hermes.Ari.status()
    on_exit(fn -> Hermes.Ari.put_status(previous) end)
    :ok
  end

  # A 24h shift starting at 00:00 today covers "now" whatever the clock says.
  defp put_on_duty(name) do
    person = person_fixture(name: name)
    day = Date.day_of_week(Hermes.Schedule.local_naive(DateTime.utc_now()))

    shift_fixture(
      person_id: person.id,
      day_of_week: day,
      starts_at: ~T[00:00:00],
      ends_at: ~T[00:00:00]
    )

    person
  end

  # In tests nothing is connected to Asterisk, so the monitor reports a
  # problem. Where the healthy case is the point, we say so explicitly.
  defp assume_healthy(lv) do
    Phoenix.PubSub.broadcast(
      Hermes.PubSub,
      "telephony",
      {:telephony_status, %{ready?: true, ari: :connected, trunk: :online, since: nil}}
    )

    render(lv)
    lv
  end

  test "requires login" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/")
  end

  describe "the global switch" do
    test "is on by default and says who gets the calls", %{conn: conn} do
      put_on_duty("Anna")

      {:ok, lv, _html} = live(conn, ~p"/")
      assume_healthy(lv)

      assert has_element?(lv, "#forwarding", "Weiterleitung läuft")
      assert has_element?(lv, "#forwarding-explanation", "Anrufe gehen an Anna")
      assert has_element?(lv, "#forwarding-switch[checked]")
    end

    test "switches forwarding off and back on", %{conn: conn} do
      put_on_duty("Anna")
      {:ok, lv, _html} = live(conn, ~p"/")

      html = lv |> element("#forwarding-switch") |> render_click()

      assert html =~ "Weiterleitung pausiert"
      assert html =~ "Anrufer hören ab sofort die Ansage"
      refute Settings.get().forwarding_enabled
      assert has_element?(lv, "#on-duty-paused")

      html = lv |> element("#forwarding-switch") |> render_click()

      assert html =~ "Weiterleitung läuft"
      assert Settings.get().forwarding_enabled
    end

    test "a switch flipped elsewhere shows up here", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      {:ok, _} = Settings.set_forwarding(false)

      assert render(lv) =~ "Weiterleitung pausiert"
    end

    test "says since when it is paused", %{conn: conn} do
      {:ok, _} = Settings.set_forwarding(false)

      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#forwarding-explanation", "Seit heute")
    end
  end

  describe "who is on duty" do
    test "warns when nobody is on duty", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      assume_healthy(lv)

      assert has_element?(lv, "#on-duty-none", "Anrufer hören die Ansage")
      assert has_element?(lv, "#forwarding-explanation", "niemand Dienst")
    end

    test "lists people in call order", %{conn: conn} do
      anna = put_on_duty("Anna")
      bert = put_on_duty("Bert")

      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#on-duty-#{anna.id}", "Anna")
      assert has_element?(lv, "#on-duty-#{bert.id}", "Bert")
      assert render(lv) =~ "in dieser Reihenfolge wird angerufen"
    end

    test "updates when the plan changes", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      put_on_duty("Neu")

      assert has_element?(lv, "#on-duty-list", "Neu")
    end

    test "names the next change", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      assert has_element?(lv, "#next-change")
    end
  end

  describe "technology" do
    test "a problem is the first thing the explanation mentions", %{conn: conn} do
      put_on_duty("Anna")
      Hermes.Ari.put_status(:disconnected)

      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#forwarding-explanation", "Technik meldet ein Problem")
    end

    test "spells out what is wrong, in plain words", %{conn: conn} do
      Hermes.Ari.put_status(:disconnected)

      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, ~s(#status-ari[data-ok="false"]), "Telefonanlage")
      assert has_element?(lv, ~s(#status-trunk[data-ok="false"]), "Fritz!Box")
      assert render(lv) =~ "können Anrufe nicht weitergeleitet werden"
      refute render(lv) =~ "Amt"
    end

    test "reacts to the monitor reporting a change", %{conn: conn} do
      Hermes.Ari.put_status(:disconnected)
      {:ok, lv, _html} = live(conn, ~p"/")

      Phoenix.PubSub.broadcast(
        Hermes.PubSub,
        "telephony",
        {:telephony_status, %{ready?: true, ari: :connected, trunk: :online, since: nil}}
      )

      assert render(lv) =~ "antwortet"
      assert has_element?(lv, ~s(#status-trunk[data-ok="true"]))
    end
  end

  describe "setup checklist" do
    test "shows the open steps", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, ~s(#check-clip[data-done="false"]))
      assert has_element?(lv, ~s(#check-people[data-done="false"]))
      assert has_element?(lv, ~s(#check-shifts[data-done="false"]))
    end

    test "disappears once everything is set up", %{conn: conn} do
      {:ok, _} = Settings.update(%{clip_number: "030 1234567"})
      put_on_duty("Anna")

      {:ok, lv, _html} = live(conn, ~p"/")

      refute has_element?(lv, "#setup-checklist")
    end

    test "does not count inactive people", %{conn: conn} do
      person_fixture(active: false)
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, ~s(#check-people[data-done="false"]))
    end
  end

  describe "recent calls" do
    test "are hidden while there are none", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      refute has_element?(lv, "#recent-calls")
    end

    test "show the newest five with their result", %{conn: conn} do
      for index <- 1..6 do
        {:ok, _} =
          Log.record(%{
            channel_id: "chan-#{index}",
            caller_number: "+4930123456#{index}",
            started_at:
              DateTime.utc_now() |> DateTime.add(-index, :minute) |> DateTime.truncate(:second),
            result: :bridged
          })
      end

      {:ok, lv, html} = live(conn, ~p"/")

      assert has_element?(lv, "#recent-calls")
      assert html =~ "Vermittelt"
      # five of six calls are listed
      assert html |> String.split(~s(id="recent-call-)) |> length() == 6
    end
  end
end
