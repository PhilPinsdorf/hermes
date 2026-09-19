defmodule HermesWeb.UserManagementLiveTest do
  use HermesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hermes.AccountsFixtures

  alias Hermes.Accounts

  setup :register_and_log_in_user

  test "public registration does not exist" do
    assert get(build_conn(), "/users/register").status == 404
  end

  describe "Index" do
    test "lists users and marks the current one", %{conn: conn, user: user} do
      other = user_fixture()
      {:ok, _lv, html} = live(conn, ~p"/users")

      assert html =~ user.email
      assert html =~ other.email
      assert html =~ "du"
    end

    test "deletes another user", %{conn: conn} do
      other = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users")

      html =
        lv
        |> element("#users-#{other.id} a", "Löschen")
        |> render_click()

      assert html =~ "#{other.email} wurde gelöscht."
      refute Accounts.get_user_by_email(other.email)
    end

    test "offers no delete or password link for oneself", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users")

      refute has_element?(lv, "#users-#{user.id} a", "Löschen")
      refute has_element?(lv, "#users-#{user.id} a", "Passwort setzen")
      assert has_element?(lv, "#users-#{user.id} a", "Mein Konto")
    end
  end

  describe "Form :new" do
    test "creates a user who can log in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/new")

      assert {:ok, _index, html} =
               lv
               |> form("#user-form",
                 user: %{email: "neu@example.com", password: "ein langes passwort"}
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/users")

      assert html =~ "neu@example.com wurde angelegt."
      assert Accounts.get_user_by_email_and_password("neu@example.com", "ein langes passwort")
    end

    test "validates input", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/new")

      html =
        lv
        |> form("#user-form", user: %{email: "kaputt", password: "kurz"})
        |> render_change()

      assert html =~ "muss ein @ enthalten"
      assert html =~ "muss mindestens 12 Zeichen lang sein"
    end
  end

  describe "Form :password" do
    test "sets a new password for another user and ends their sessions", %{conn: conn} do
      other = user_fixture()
      token = Accounts.generate_user_session_token(other)

      {:ok, lv, _html} = live(conn, ~p"/users/#{other}/password")

      assert {:ok, _index, html} =
               lv
               |> form("#user-form", user: %{password: "ganz neues passwort"})
               |> render_submit()
               |> follow_redirect(conn, ~p"/users")

      assert html =~ "Passwort für #{other.email} wurde gesetzt."
      assert Accounts.get_user_by_email_and_password(other.email, "ganz neues passwort")
      refute Accounts.get_user_by_session_token(token)
    end

    test "redirects to the account page for one's own password", %{conn: conn, user: user} do
      assert {:error, {:live_redirect, %{to: "/users/settings"}}} =
               live(conn, ~p"/users/#{user}/password")
    end
  end
end
