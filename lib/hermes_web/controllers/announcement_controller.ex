defmodule HermesWeb.AnnouncementController do
  use HermesWeb, :controller

  alias Hermes.Sounds

  @doc """
  Plays back an announcement in the browser, so one can listen to it before a
  caller does.
  """
  def show(conn, %{"name" => name}) do
    with {:ok, name} <- parse_name(name),
         path = Sounds.file(name),
         true <- File.exists?(path) do
      conn
      |> put_resp_content_type("audio/wav")
      # Play in the browser instead of downloading.
      |> put_resp_header("content-disposition", "inline")
      |> put_resp_header("cache-control", "no-store")
      |> send_file(200, path)
    else
      _ ->
        conn
        |> put_flash(:error, "Diese Ansage gibt es noch nicht.")
        |> redirect(to: ~p"/settings")
    end
  end

  defp parse_name(name) do
    case Enum.find(Sounds.names(), &(to_string(&1) == name)) do
      nil -> :error
      name -> {:ok, name}
    end
  end
end
