defmodule HermesWeb.Https do
  @moduledoc """
  Forces HTTPS — but only where there is HTTPS at all.

  Hermes is reached in several ways (see `docs/rollout.md`): publicly through a
  Cloudflare Tunnel (or any other reverse proxy), plainly in the LAN, or over
  Tailscale. Only the public one has TLS. Phoenix' built-in `:force_ssl` is a
  compile-time option, so with it the same image could not serve both; every
  LAN test would be redirected to a `https://` address where nothing listens.

  This plug decides at runtime instead, from the address the installation is
  configured with (`PHX_URL_SCHEME` in `.env`):

    * `https` → redirect http to https and send HSTS
    * anything else → do nothing

  Requests that already arrived over TLS — in practice: forwarded by the tunnel
  or proxy with `X-Forwarded-Proto: https` — pass through untouched.
  `localhost` is excluded, so the container's own health check keeps working.

  Should a proxy not send that header, the redirect would bounce back and forth
  between it and Hermes. `HTTPS_REDIRECT=false` in `.env` switches only the
  redirect off; the secure cookie and HSTS stay.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if enabled?() and redirect?() do
      Plug.SSL.call(conn, ssl_options())
    else
      conn
    end
  end

  @doc """
  Whether this installation is reached over HTTPS.
  """
  def enabled? do
    # Read from the application environment, not from the endpoint's cached
    # config: the value comes from runtime.exs and must stay changeable.
    :hermes
    |> Application.get_env(HermesWeb.Endpoint, [])
    |> Keyword.get(:url, [])
    |> Keyword.get(:scheme) == "https"
  end

  @doc """
  Whether Hermes redirects to https itself. Off for a proxy that terminates TLS
  without saying so in `X-Forwarded-Proto` (it would loop otherwise).
  """
  def redirect?, do: Application.get_env(:hermes, :https_redirect, true)

  @doc """
  Session cookie options: on an HTTPS installation the cookie is marked
  `Secure`, so it never travels over an unencrypted connection. In the LAN it
  must not be, otherwise no one could log in.
  """
  def session_options do
    Keyword.put(HermesWeb.Endpoint.base_session_options(), :secure, enabled?())
  end

  # Built per request: the configuration is only known at runtime.
  defp ssl_options do
    Plug.SSL.init(
      rewrite_on: [:x_forwarded_proto],
      # The health check inside the container speaks plain HTTP.
      exclude: ["localhost", "127.0.0.1"],
      hsts: true
    )
  end
end
