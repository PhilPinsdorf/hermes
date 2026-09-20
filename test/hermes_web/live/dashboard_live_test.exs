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
end
