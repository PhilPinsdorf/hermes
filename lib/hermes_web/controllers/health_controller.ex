defmodule HermesWeb.HealthController do
  use HermesWeb, :controller

  alias Hermes.Telephony.Monitor

  @doc """
  Liveness/readiness probe for Docker.

  Returns 200 while the application itself works, so a phone line problem
  does not make Docker restart a perfectly healthy container. What telephony
  is doing is reported in the body (and in the web UI).
  """
  def show(conn, _params) do
    case Ecto.Adapters.SQL.query(Hermes.Repo, "SELECT 1", []) do
      {:ok, _} ->
        telephony = Monitor.status()

        json(conn, %{
          status: "ok",
          telephony: %{
            ready: telephony.ready?,
            ari: telephony.ari,
            trunk: telephony.trunk
          }
        })

      {:error, _} ->
        conn |> put_status(:service_unavailable) |> json(%{status: "database unavailable"})
    end
  end
end
