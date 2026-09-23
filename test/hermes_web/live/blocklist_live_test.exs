defmodule HermesWeb.BlocklistLiveTest do
  use HermesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Hermes.Blocklist

  setup :register_and_log_in_user

  test "requires login" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/blocked")
  end

  test "shows an empty state", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/blocked")
    assert has_element?(lv, "#blocked-empty")
  end

  test "the button opens the dialog", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/blocked")

    refute has_element?(lv, "#block-modal")

    lv |> element("a", "Nummer blockieren") |> render_click()

    assert_patch(lv, ~p"/blocked/new")
    assert has_element?(lv, "#block-modal #block-form")
  end

  test "blocks a number through the dialog", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/blocked/new")

    lv
    |> form("#block-form", blocked_number: %{number: "0171 1234567", note: "Werbung"})
    |> render_submit()

    assert_patch(lv, ~p"/blocked")

    assert [%{number: "+491711234567", note: "Werbung"}] = Blocklist.list()

    html = render(lv)
    assert html =~ "+49 1711234567"
    assert html =~ "Werbung"
    refute html =~ "Keine Nummer blockiert."
  end

  test "says so when the number is already blocked", %{conn: conn} do
    {:ok, _} = Blocklist.block(%{number: "+491711234567"})
    {:ok, lv, _html} = live(conn, ~p"/blocked/new")

    html =
      lv
      |> form("#block-form", blocked_number: %{number: "0171 1234567"})
      |> render_submit()

    assert html =~ "ist bereits blockiert"
    assert length(Blocklist.list()) == 1
  end

  test "frees a number again", %{conn: conn} do
    {:ok, entry} = Blocklist.block(%{number: "+491711234567"})
    {:ok, lv, _html} = live(conn, ~p"/blocked")

    lv |> element("#blocked-#{entry.id} a", "Freigeben") |> render_click()

    assert Blocklist.list() == []
    assert has_element?(lv, "#blocked-empty")
  end
end
