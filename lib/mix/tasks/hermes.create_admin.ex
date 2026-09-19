defmodule Mix.Tasks.Hermes.CreateAdmin do
  @shortdoc "Creates a web UI user (development)"

  @moduledoc """
  Creates a web UI user.

      mix hermes.create_admin admin@example.com

  The password is prompted for. In a deployed container there is no Mix;
  use `docker compose exec -it app bin/create_admin EMAIL` instead.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run([email]) do
    password = Mix.shell().prompt("Passwort (mind. 12 Zeichen):") |> String.trim()

    case Hermes.Release.create_user(email, password) do
      {:ok, user} -> Mix.shell().info("Benutzer #{user.email} angelegt.")
      {:error, message} -> Mix.raise(message)
    end
  end

  def run(_args), do: Mix.raise("usage: mix hermes.create_admin EMAIL")
end
