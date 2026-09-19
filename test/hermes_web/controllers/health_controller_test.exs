defmodule HermesWeb.HealthControllerTest do
  use HermesWeb.ConnCase, async: true

  test "GET /healthz returns ok", %{conn: conn} do
    conn = get(conn, ~p"/healthz")
    assert text_response(conn, 200) == "ok"
  end
end
