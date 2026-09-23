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

      lv |> element("#delete-user-#{other.id}") |> render_click()
      assert has_element?(lv, "#confirm-delete-user", other.email)

      html = lv |> element("#confirm-delete-user-confirm") |> render_click()

      assert html =~ "#{other.email} wurde gelöscht."
      refute Accounts.get_user_by_email(other.email)
    end

    test "marks your own row instead of offering a delete button",
         %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users")

      refute has_element?(lv, "#delete-user-#{user.id}")
      assert has_element?(lv, "#users-#{user.id} .badge", "du")
      # The account page is reached from the header, not from this table.
      refute render(lv) =~ "Mein Konto"
    end

    test "offers no password link for other users", %{conn: conn} do
      other = user_fixture()
      {:ok, lv, html} = live(conn, ~p"/users")

      refute html =~ "Passwort"
      refute has_element?(lv, ~s(a[href="/users/#{other.id}/password"]))
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

  describe "no editing of other users' passwords" do
    test "there is no route to set another user's password", %{conn: conn} do
      other = user_fixture()
      assert get(conn, "/users/#{other.id}/password").status == 404
    end
  end
end
