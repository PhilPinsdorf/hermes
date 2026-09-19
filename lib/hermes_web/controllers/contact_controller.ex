defmodule HermesWeb.ContactController do
  use HermesWeb, :controller

  alias Hermes.Settings

  @doc """
  Serves the one global vCard that every on-duty person imports.
  """
  def show(conn, _params) do
    case Settings.vcard(Settings.get()) do
      {:ok, vcard} ->
        send_download(conn, {:binary, vcard},
          filename: "hermes-kontakt.vcf",
          content_type: "text/vcard"
        )

      {:error, :no_clip_number} ->
        conn
        |> put_flash(:error, "Bitte zuerst die angezeigte Rufnummer speichern.")
        |> redirect(to: ~p"/settings")
    end
  end
end
