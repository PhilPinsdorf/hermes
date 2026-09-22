defmodule HermesWeb.NavigationTest do
  use HermesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  # Which navigation entry is marked as the current page?
  defp current(lv) do
    lv
    |> render()
    |> then(&Regex.scan(~r/href="([^"]+)"[^>]*aria-current="page"/, &1))
    |> Enum.map(fn [_, href] -> href end)
    |> Enum.uniq()
  end

  test "the account page marks Konto, not Benutzer", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    assert current(lv) == ["/users/settings"]
  end

  test "the user list marks Benutzer", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users")
    assert current(lv) == ["/users"]
  end

  test "a subpage marks its section", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/people/new")
    assert current(lv) == ["/people"]

    {:ok, lv, _html} = live(conn, ~p"/schedule/overrides")
    assert current(lv) == ["/schedule"]
  end

  test "the overview is only marked on the overview", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")
    assert current(lv) == ["/"]

    {:ok, lv, _html} = live(conn, ~p"/calls")
    assert current(lv) == ["/calls"]
  end

  test "the scrollable navigation keeps the current entry in view", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users")

    assert has_element?(lv, "#mobile-nav[phx-hook]")
  end
end
