defmodule HermesWeb.HealthController do
  use HermesWeb, :controller

  @doc """
  Reports 200 when the application and its database are reachable, 503 otherwise.
  """
  def show(conn, _params) do
    case Ecto.Adapters.SQL.query(Hermes.Repo, "SELECT 1", []) do
      {:ok, _} -> text(conn, "ok")
      {:error, _} -> conn |> put_status(:service_unavailable) |> text("database unavailable")
    end
  end
end
