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
end
