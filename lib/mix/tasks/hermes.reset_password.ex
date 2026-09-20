defmodule Mix.Tasks.Hermes.ResetPassword do
  @shortdoc "Sets a new password for a web UI user (development)"

  @moduledoc """
  Sets a new password for a web UI user and ends all of their sessions.

      mix hermes.reset_password user@example.com

  The password is prompted for. In a deployed container there is no Mix;
  use `docker compose exec -it app bin/reset_password EMAIL` instead.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run([email]) do
    password = Mix.shell().prompt("Neues Passwort (mind. 12 Zeichen):") |> String.trim()

    case Hermes.Release.reset_user_password(email, password) do
      {:ok, user} -> Mix.shell().info("Benutzer #{user.email} hat ein neues Passwort.")
      {:error, message} -> Mix.raise(message)
    end
  end

  def run(_args), do: Mix.raise("usage: mix hermes.reset_password EMAIL")
end
