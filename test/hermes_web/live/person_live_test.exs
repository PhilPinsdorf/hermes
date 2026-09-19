defmodule HermesWeb.PersonLiveTest do
  use HermesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hermes.DirectoryFixtures

  alias Hermes.Directory

  setup :register_and_log_in_user

  test "requires login", %{conn: _conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/people")
  end

  describe "Index" do
    test "shows an empty state", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/people")
      assert html =~ "Noch keine Personen angelegt."
    end

    test "lists people with formatted numbers", %{conn: conn} do
      person_fixture(name: "Anna Muster", phone_e164: "0171 1234567", ring_timeout_seconds: 30)
      person_fixture(name: "Bert Inaktiv", active: false)

      {:ok, _lv, html} = live(conn, ~p"/people")

      assert html =~ "Anna Muster"
      assert html =~ "+49 1711234567"
      assert html =~ "30 s"
      assert html =~ "inaktiv"
    end

    test "deletes a person", %{conn: conn} do
      person = person_fixture(name: "Weg Damit")
      {:ok, lv, _html} = live(conn, ~p"/people")

      html =
        lv
        |> element("#people-#{person.id} a", "Löschen")
        |> render_click()

      assert html =~ "Weg Damit wurde gelöscht."
      assert Directory.list_people() == []
    end

    test "updates when a person is created elsewhere", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/people")
      person_fixture(name: "Neu Von Woanders")
      assert render(lv) =~ "Neu Von Woanders"
    end
  end

  describe "Form" do
    test "creates a person and normalizes the number", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/people/new")

      assert {:ok, _index, html} =
               lv
               |> form("#person-form",
                 person: %{name: "Clara", phone_e164: "0171 / 765 43 21"}
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/people")

      assert html =~ "Person angelegt."
      assert [%{name: "Clara", phone_e164: "+491717654321"}] = Directory.list_people()
    end

    test "shows validation errors while typing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/people/new")

      html =
        lv
        |> form("#person-form", person: %{name: "", phone_e164: "123"})
        |> render_change()

      assert html =~ "darf nicht leer sein"
      assert html =~ "braucht eine Vorwahl"
    end

    test "shows the global ring timeout as placeholder", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/people/new")
      assert html =~ "Standard: 25 s"
    end

    test "edits a person", %{conn: conn} do
      person = person_fixture(name: "Alt")
      {:ok, lv, _html} = live(conn, ~p"/people/#{person}/edit")

      assert {:ok, _index, _html} =
               lv
               |> form("#person-form", person: %{name: "Neu", active: false})
               |> render_submit()
               |> follow_redirect(conn, ~p"/people")

      assert %{name: "Neu", active: false} = Directory.get_person!(person.id)
    end
  end
end
