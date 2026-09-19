defmodule Hermes.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :hermes

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Creates a web UI user from `HERMES_ADMIN_EMAIL` / `HERMES_ADMIN_PASSWORD`.
  Called by `bin/create_admin`, which prompts for the password.
  """
  def create_admin do
    load_app()
    email = System.fetch_env!("HERMES_ADMIN_EMAIL")
    password = System.fetch_env!("HERMES_ADMIN_PASSWORD")

    [repo | _] = repos()
    {:ok, result, _} = Ecto.Migrator.with_repo(repo, fn _ -> create_user(email, password) end)

    case result do
      {:ok, user} ->
        IO.puts("Benutzer #{user.email} angelegt.")

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  @doc """
  Creates a user and returns `{:ok, user}` or `{:error, human_readable_message}`.
  Shared by the release task and `mix hermes.create_admin`.
  """
  def create_user(email, password) do
    case Hermes.Accounts.create_user(%{email: email, password: password}) do
      {:ok, user} ->
        {:ok, user}

      {:error, changeset} ->
        # Same German messages as in the web UI.
        errors =
          Ecto.Changeset.traverse_errors(changeset, &HermesWeb.CoreComponents.translate_error/1)

        {:error,
         Enum.map_join(errors, "\n", fn {field, msgs} ->
           "#{field}: #{Enum.join(msgs, ", ")}"
         end)}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
