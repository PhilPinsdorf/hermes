defmodule HermesWeb.OverrideLiveTest do
  use HermesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hermes.DirectoryFixtures
  import Hermes.ScheduleFixtures

  alias Hermes.Schedule

  setup :register_and_log_in_user

  test "requires login" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(build_conn(), ~p"/schedule/overrides")
  end

  test "shows an empty state", %{conn: conn} do
    person_fixture()
    {:ok, lv, _html} = live(conn, ~p"/schedule/overrides")
    assert has_element?(lv, "#overrides-empty")
  end

  test "creates a holiday", %{conn: conn} do
    person = person_fixture(name: "Anna")
    {:ok, lv, _html} = live(conn, ~p"/schedule/overrides")

    html =
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

    assert html =~ "Ausnahme gespeichert."
    assert html =~ "Sommerurlaub"
    assert html =~ "abwesend"
    assert html =~ "01.07.2099 00:00"

    assert [%{kind: :block, note: "Sommerurlaub"}] = Schedule.list_upcoming_overrides()
  end

  test "validates the interval", %{conn: conn} do
    person = person_fixture()
    {:ok, lv, _html} = live(conn, ~p"/schedule/overrides")

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
  end

  test "deletes an override", %{conn: conn} do
    override = override_fixture()
    {:ok, lv, _html} = live(conn, ~p"/schedule/overrides")

    lv |> element("#overrides-#{override.id} a", "Löschen") |> render_click()

    assert Schedule.list_upcoming_overrides() == []
  end
end
