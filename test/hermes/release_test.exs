defmodule Hermes.ReleaseTest do
  use Hermes.DataCase, async: true

  alias Hermes.Release

  describe "create_user/2" do
    test "creates a user" do
      assert {:ok, user} = Release.create_user("admin@example.com", "ein sicheres passwort")
      assert Hermes.Accounts.get_user_by_email_and_password(user.email, "ein sicheres passwort")
    end

    test "returns readable errors" do
      assert {:error, message} = Release.create_user("kaputt", "kurz")
      assert message =~ "email: muss ein @ enthalten"
      assert message =~ "password: muss mindestens 12 Zeichen lang sein"
    end
  end

  describe "reset_user_password/2" do
    test "sets a new password and ends all sessions" do
      {:ok, user} = Release.create_user("vergessen@example.com", "altes passwort 123")
      token = Hermes.Accounts.generate_user_session_token(user)

      assert {:ok, _} = Release.reset_user_password("vergessen@example.com", "neues passwort 456")
      assert Hermes.Accounts.get_user_by_email_and_password(user.email, "neues passwort 456")
      refute Hermes.Accounts.get_user_by_email_and_password(user.email, "altes passwort 123")
      refute Hermes.Accounts.get_user_by_session_token(token)
    end

    test "reports an unknown email" do
      assert {:error, "Es gibt keinen Benutzer mit der E-Mail nie@example.com."} =
               Release.reset_user_password("nie@example.com", "neues passwort 456")
    end

    test "validates the new password" do
      {:ok, _} = Release.create_user("kurz@example.com", "altes passwort 123")

      assert {:error, "password: muss mindestens 12 Zeichen lang sein"} =
               Release.reset_user_password("kurz@example.com", "kurz")
    end
  end
end
