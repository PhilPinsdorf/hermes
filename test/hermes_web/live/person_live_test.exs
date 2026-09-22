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

    test "the list does not delete; that happens while editing", %{conn: conn} do
      person = person_fixture(name: "Bleibt Erstmal")
      {:ok, lv, _html} = live(conn, ~p"/people")

      refute has_element?(lv, "#people-#{person.id} button", "Löschen")
      refute render(lv) =~ "Löschen"
    end

    test "updates when a person is created elsewhere", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/people")
      person_fixture(name: "Neu Von Woanders")
      assert render(lv) =~ "Neu Von Woanders"
    end
  end

  describe "cards on a phone" do
    test "name, number and ring duration, with coloured actions", %{conn: conn} do
      person = person_fixture(name: "Anna Muster", phone_e164: "0171 1234567")

      {:ok, lv, _html} = live(conn, ~p"/people")

      card = "#person-card-#{person.id}"
      assert has_element?(lv, card <> " h2", "Anna Muster")
      assert has_element?(lv, card, "+49 1711234567")
      assert has_element?(lv, card, "Klingeldauer: 25 s (Standard)")
      assert has_element?(lv, card <> " a.btn-primary", "Bearbeiten")
    end

    test "an own ring duration is shown instead of the default", %{conn: conn} do
      person = person_fixture(ring_timeout_seconds: 45)

      {:ok, lv, _html} = live(conn, ~p"/people")

      assert has_element?(lv, "#person-card-#{person.id}", "Klingeldauer: 45 s")
      refute render(lv) =~ "45 s (Standard)"
    end

    test "a card offers editing only", %{conn: conn} do
      person = person_fixture(name: "Anna")

      {:ok, lv, _html} = live(conn, ~p"/people")

      assert has_element?(lv, "#person-card-#{person.id} a", "Bearbeiten")
      refute has_element?(lv, "#person-card-#{person.id} button", "Löschen")
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

    test "deletes a person from the edit screen", %{conn: conn} do
      person = person_fixture(name: "Weg Damit")
      {:ok, lv, _html} = live(conn, ~p"/people/#{person}/edit")

      assert {:ok, _index, html} =
               lv
               |> element("#delete-person")
               |> render_click()
               |> follow_redirect(conn, ~p"/people")

      assert html =~ "Weg Damit wurde gelöscht."
      assert Directory.list_people() == []
    end

    test "creating offers no delete button", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/people/new")
      refute has_element?(lv, "#delete-person")
    end

    test "warns that shifts disappear with the person", %{conn: conn} do
      person = person_fixture(name: "Anna")
      {:ok, lv, _html} = live(conn, ~p"/people/#{person}/edit")

      assert lv |> element("#delete-person") |> render() =~ "Schichten"
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
