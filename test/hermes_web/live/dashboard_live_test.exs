defmodule HermesWeb.DashboardLiveTest do
  use HermesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hermes.DirectoryFixtures

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
end
