defmodule HermesWeb.SystemDashboardTest do
  use HermesWeb.ConnCase, async: true

  test "the system page requires a login", %{conn: conn} do
    conn = get(conn, ~p"/system")
    assert redirected_to(conn) =~ "/users/log-in"
  end

  test "logged in users can open it", %{conn: conn} do
    conn = conn |> log_in_user(Hermes.AccountsFixtures.user_fixture()) |> get(~p"/system")

    # LiveDashboard redirects to its first page.
    assert conn.status in [200, 302]
  end
end
