defmodule HermesWeb.Branding do
  @moduledoc """
  Makes the appearance of this installation available to every page: as a plug
  for normal requests and as an `on_mount` hook for LiveViews, so the settings
  are read once per request instead of once per rendered component.
  """

  alias Hermes.Branding

  @doc false
  def init(opts), do: opts

  @doc "Plug: puts `:branding` into the connection."
  def call(conn, _opts), do: Plug.Conn.assign(conn, :branding, Branding.summary())

  @doc """
  LiveView hook: puts `:branding` and the current path into the socket. The
  path is what the navigation uses to mark the page one is on.
  """
  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> Phoenix.Component.assign(:branding, Branding.summary())
      |> Phoenix.Component.assign(:current_path, nil)
      |> Phoenix.LiveView.attach_hook(:current_path, :handle_params, &put_current_path/3)

    {:cont, socket}
  end

  defp put_current_path(_params, uri, socket) do
    {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(uri).path)}
  end
end
