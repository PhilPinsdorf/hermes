defmodule HermesWeb.ScheduleLiveTest do
  use HermesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hermes.DirectoryFixtures
  import Hermes.ScheduleFixtures

  alias Hermes.Schedule

  setup :register_and_log_in_user

  test "requires login" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/schedule")
  end

  describe "grid" do
    test "renders shifts in their day column", %{conn: conn} do
      person = person_fixture(name: "Anna")
      shift = shift_fixture(person_id: person.id, day_of_week: 3)

      {:ok, lv, _html} = live(conn, ~p"/schedule")

      assert has_element?(lv, "#day-3 #shift-#{shift.id}-3", "Anna")
      assert has_element?(lv, "#shift-#{shift.id}-3", "08:00–16:00")
    end

    test "shows an overnight shift in both columns", %{conn: conn} do
      shift = shift_fixture(day_of_week: 7, starts_at: ~T[22:00:00], ends_at: ~T[06:00:00])

      {:ok, lv, _html} = live(conn, ~p"/schedule")

      assert has_element?(lv, "#day-7 #shift-#{shift.id}-7")
      assert has_element?(lv, "#day-1 #shift-#{shift.id}-1", "bis 06:00")
    end

    test "shows a now marker", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/schedule")
      assert has_element?(lv, "#now-marker")
    end

    test "updates when the plan changes elsewhere", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/schedule")
      person = person_fixture(name: "Von Woanders")
      shift_fixture(person_id: person.id)

      assert render(lv) =~ "Von Woanders"
    end
  end

  describe "legend" do
    test "shows names as chips, not as uppercase status tags", %{conn: conn} do
      person_fixture(name: "Anna Muster")

      {:ok, lv, html} = live(conn, ~p"/schedule")

      assert has_element?(lv, "#legend .person-chip", "Anna Muster")
      refute html =~ ~s(class="badge)
    end
  end

  describe "on a phone" do
    test "shows a list per day instead of the grid", %{conn: conn} do
      person = person_fixture(name: "Anna")
      shift = shift_fixture(person_id: person.id, day_of_week: 3)

      {:ok, lv, _html} = live(conn, ~p"/schedule")

      # The grid stays in the markup for wide screens, the list is the phone view.
      assert has_element?(lv, "#schedule-days")
      assert has_element?(lv, "#day-list-3 a[href='/schedule/shifts/#{shift.id}/edit']", "Anna")
      assert has_element?(lv, "#day-list-1", "frei")
    end

    test "marks a shift that continues from the night before", %{conn: conn} do
      person = person_fixture(name: "Nacht")

      shift_fixture(
        person_id: person.id,
        day_of_week: 2,
        starts_at: ~T[22:00:00],
        ends_at: ~T[06:00:00]
      )

      {:ok, lv, _html} = live(conn, ~p"/schedule")

      assert has_element?(lv, "#day-list-2", "22:00–06:00")
      assert has_element?(lv, "#day-list-3", "aus der Nacht")
    end
  end

  describe "creating by dragging" do
    test "a selection opens the form pre-filled", %{conn: conn} do
      person_fixture()
      {:ok, lv, _html} = live(conn, ~p"/schedule")

      render_hook(lv, "select_range", %{"day" => 2, "from" => 1320, "to" => 1440})

      assert_patch(lv, ~p"/schedule/shifts/new?day=2&from=22%3A00&to=00%3A00")

      assert has_element?(
               lv,
               "#shift-form select[name='shift[day_of_week]'] option[selected][value='2']"
             )

      assert has_element?(lv, "#shift-form input[name='shift[starts_at]'][value^='22:00']")
      assert has_element?(lv, "#overnight-hint", "Endet um Mitternacht.")
    end

    test "saves the shift", %{conn: conn} do
      person = person_fixture(name: "Anna")
      {:ok, lv, _html} = live(conn, ~p"/schedule/shifts/new?day=5&from=20:00&to=06:00")

      assert has_element?(lv, "#overnight-hint", "bis Samstag, 06:00")

      lv
      |> form("#shift-form", shift: %{person_id: person.id})
      |> render_submit()

      assert_patch(lv, ~p"/schedule")
      assert render(lv) =~ "Schicht gespeichert."

      assert [%{day_of_week: 5, starts_at: ~T[20:00:00], ends_at: ~T[06:00:00]}] =
               Schedule.list_shifts()
    end

    test "requires a person", %{conn: conn} do
      person_fixture()
      {:ok, lv, _html} = live(conn, ~p"/schedule/shifts/new")

      html = lv |> form("#shift-form", shift: %{person_id: ""}) |> render_submit()
      assert html =~ "darf nicht leer sein"
      assert Schedule.list_shifts() == []
    end

    test "explains that a person is needed first", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/schedule/shifts/new")
      assert html =~ "Zuerst eine Person anlegen"
    end
  end

  describe "editing" do
    test "clicking a shift opens it, saving updates it", %{conn: conn} do
      shift = shift_fixture()
      {:ok, lv, _html} = live(conn, ~p"/schedule")

      lv |> element("#shift-#{shift.id}-1") |> render_click()
      assert_patch(lv, ~p"/schedule/shifts/#{shift.id}/edit")

      lv
      |> form("#shift-form", shift: %{starts_at: "09:30", ends_at: "09:30"})
      |> render_change()

      assert has_element?(lv, "#overnight-hint", "24 Stunden")

      lv |> form("#shift-form") |> render_submit()

      assert %{starts_at: ~T[09:30:00], ends_at: ~T[09:30:00]} = Schedule.get_shift!(shift.id)
    end

    test "deletes a shift", %{conn: conn} do
      shift = shift_fixture()
      {:ok, lv, _html} = live(conn, ~p"/schedule/shifts/#{shift.id}/edit")

      lv |> element("#delete-shift") |> render_click()

      assert_patch(lv, ~p"/schedule")
      assert Schedule.list_shifts() == []
      refute has_element?(lv, "#shift-#{shift.id}-1")
    end
  end

  describe "exceptions" do
    test "are listed under the plan", %{conn: conn} do
      person = person_fixture()
      {:ok, lv, _html} = live(conn, ~p"/schedule")
      assert has_element?(lv, "#overrides-empty")

      override = override_fixture(person_id: person.id, note: "Sommerurlaub")
      {:ok, lv, _html} = live(conn, ~p"/schedule")

      refute has_element?(lv, "#overrides-empty")
      assert has_element?(lv, "#override-#{override.id}", "Sommerurlaub")
    end

    test "the button opens the dialog", %{conn: conn} do
      person_fixture()
      {:ok, lv, _html} = live(conn, ~p"/schedule")

      refute has_element?(lv, "#override-modal")

      lv |> element("a", "Ausnahme anlegen") |> render_click()

      assert_patch(lv, ~p"/schedule/overrides/new")
      assert has_element?(lv, "#override-modal #override-form")
    end

    test "a holiday is created through the dialog", %{conn: conn} do
      person = person_fixture(name: "Anna")
      {:ok, lv, _html} = live(conn, ~p"/schedule/overrides/new")

      lv
      |> form("#override-form",
        override: %{
          person_id: person.id,
          kind: "block",
          starts_at: "2099-07-01T00:00",
          ends_at: "2099-07-15T00:00",
          note: "Sommerurlaub"
        }
      )
      |> render_submit()

      assert_patch(lv, ~p"/schedule")
      assert [%{kind: :block, note: "Sommerurlaub"}] = Schedule.list_upcoming_overrides()

      html = render(lv)
      assert html =~ "Sommerurlaub"
      assert html =~ "abwesend"
      assert html =~ "01.07.2099 00:00"
    end

    test "the interval is validated in the dialog", %{conn: conn} do
      person = person_fixture()
      {:ok, lv, _html} = live(conn, ~p"/schedule/overrides/new")

      html =
        lv
        |> form("#override-form",
          override: %{
            person_id: person.id,
            starts_at: "2099-07-02T00:00",
            ends_at: "2099-07-01T00:00"
          }
        )
        |> render_change()

      assert html =~ "muss nach dem Beginn liegen"
      assert Schedule.list_upcoming_overrides() == []
    end

    test "an exception is deleted from the list", %{conn: conn} do
      override = override_fixture()
      {:ok, lv, _html} = live(conn, ~p"/schedule")

      lv |> element("#override-#{override.id} a", "Löschen") |> render_click()

      assert Schedule.list_upcoming_overrides() == []
      assert has_element?(lv, "#overrides-empty")
    end
  end
end
