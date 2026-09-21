defmodule HermesWeb.ContactController do
  use HermesWeb, :controller

  alias Hermes.Settings

  @doc """
  Serves the one global vCard that every on-duty person imports.
  """
  def show(conn, _params) do
    setting = Settings.get()

    case Settings.vcard(setting) do
      {:ok, vcard} ->
        send_download(conn, {:binary, vcard},
          filename: Settings.vcard_filename(setting),
          content_type: "text/vcard"
        )

      {:error, :no_clip_number} ->
        conn
        |> put_flash(:error, "Bitte zuerst die angezeigte Rufnummer speichern.")
        |> redirect(to: ~p"/settings")
    end
  end
end
