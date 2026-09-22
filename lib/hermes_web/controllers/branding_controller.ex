defmodule HermesWeb.BrandingController do
  use HermesWeb, :controller

  alias Hermes.Settings

  @doc """
  Serves the uploaded logo. Without one, there is nothing to show — the header
  then falls back to an icon.
  """
  def logo(conn, _params) do
    case Settings.get() do
      %{logo_data: data, logo_content_type: type} when is_binary(data) and is_binary(type) ->
        conn
        |> put_resp_content_type(type)
        # Cached hard; the URL carries a version marker that changes on upload.
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> send_resp(200, data)

      _ ->
        send_resp(conn, 404, "")
    end
  end
end
