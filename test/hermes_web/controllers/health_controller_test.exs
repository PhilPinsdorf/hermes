defmodule HermesWeb.HealthControllerTest do
  use HermesWeb.ConnCase, async: true

  test "GET /healthz reports the application and telephony state", %{conn: conn} do
    conn = get(conn, ~p"/healthz")

    assert %{"status" => "ok", "telephony" => telephony} = json_response(conn, 200)
    assert Map.has_key?(telephony, "ready")
    assert Map.has_key?(telephony, "ari")
    assert Map.has_key?(telephony, "trunk")
  end

  test "a phone line problem does not make the container unhealthy", %{conn: conn} do
    # ARI is never connected in tests, so telephony is not ready.
    conn = get(conn, ~p"/healthz")

    assert %{"status" => "ok", "telephony" => %{"ready" => false}} = json_response(conn, 200)
  end
end
