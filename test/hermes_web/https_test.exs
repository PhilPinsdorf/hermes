defmodule HermesWeb.HttpsTest do
  @moduledoc """
  The same image serves a LAN install over plain HTTP and a customer install
  behind a Cloudflare Tunnel over TLS. These tests pin both halves of that.
  """
  use HermesWeb.ConnCase, async: false

  alias HermesWeb.Https

  setup do
    original = Application.get_env(:hermes, HermesWeb.Endpoint)
    on_exit(fn -> Application.put_env(:hermes, HermesWeb.Endpoint, original) end)
    :ok
  end

  defp configure_scheme(scheme) do
    config = Application.get_env(:hermes, HermesWeb.Endpoint)
    url = Keyword.get(config, :url, []) |> Keyword.put(:scheme, scheme)
    Application.put_env(:hermes, HermesWeb.Endpoint, Keyword.put(config, :url, url))
  end

  describe "a LAN or Tailscale installation (http)" do
    setup do
      configure_scheme("http")
      :ok
    end

    test "serves plain HTTP without redirecting", %{conn: conn} do
      conn = get(%{conn | host: "192.168.178.91"}, ~p"/users/log-in")

      assert html_response(conn, 200)
      assert get_resp_header(conn, "strict-transport-security") == []
    end

    test "the session cookie is not marked Secure" do
      refute Https.enabled?()
      refute Keyword.get(Https.session_options(), :secure)
    end
  end

  describe "an installation behind TLS (https)" do
    setup do
      configure_scheme("https")
      :ok
    end

    test "redirects plain HTTP to HTTPS", %{conn: conn} do
      conn = get(%{conn | host: "hermes.example"}, ~p"/users/log-in")

      assert redirected_to(conn, 301) == "https://hermes.example/users/log-in"
    end

    test "lets a request through that the tunnel already terminated", %{conn: conn} do
      conn =
        %{conn | host: "hermes.example"}
        |> put_req_header("x-forwarded-proto", "https")
        |> get(~p"/users/log-in")

      assert html_response(conn, 200)
      assert [hsts] = get_resp_header(conn, "strict-transport-security")
      assert hsts =~ "max-age="
    end

    test "the health check inside the container is not redirected", %{conn: conn} do
      # The container asks http://localhost:4000/healthz; a redirect there
      # would make Docker consider a healthy container unhealthy.
      conn = get(%{conn | host: "localhost"}, ~p"/healthz")

      assert %{"status" => "ok"} = json_response(conn, 200)
    end

    test "the redirect can be switched off for a proxy that does not say so", %{conn: conn} do
      Application.put_env(:hermes, :https_redirect, false)
      on_exit(fn -> Application.put_env(:hermes, :https_redirect, true) end)

      conn = get(%{conn | host: "hermes.example"}, ~p"/users/log-in")

      assert html_response(conn, 200)
      # The cookie protection stays in place.
      assert Keyword.get(Https.session_options(), :secure)
    end

    test "the session cookie is marked Secure" do
      assert Https.enabled?()
      assert Keyword.get(Https.session_options(), :secure)
    end
  end
end
