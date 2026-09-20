defmodule Hermes.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :hermes

  alias Hermes.Accounts

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
    run_user_task(&create_user/2, "angelegt")
  end

  @doc """
  Sets a new password for `HERMES_ADMIN_EMAIL` from `HERMES_ADMIN_PASSWORD` and
  ends all of that user's sessions. Called by `bin/reset_password`.

  This is the operator's way to recover a forgotten password; users cannot
  change each other's passwords in the web UI.
  """
  def reset_password do
    run_user_task(&reset_user_password/2, "hat ein neues Passwort, alle Sitzungen wurden beendet")
  end

  defp run_user_task(fun, success) do
    load_app()
    email = System.fetch_env!("HERMES_ADMIN_EMAIL")
    password = System.fetch_env!("HERMES_ADMIN_PASSWORD")

    [repo | _] = repos()
    {:ok, result, _} = Ecto.Migrator.with_repo(repo, fn _ -> fun.(email, password) end)

    case result do
      {:ok, user} ->
        IO.puts("Benutzer #{user.email} #{success}.")

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
    case Accounts.create_user(%{email: email, password: password}) do
      {:ok, user} -> {:ok, user}
      {:error, changeset} -> {:error, format_errors(changeset)}
    end
  end

  @doc """
  Sets a new password and expires all sessions of the user. Returns `{:ok, user}`
  or `{:error, human_readable_message}`.
  """
  def reset_user_password(email, password) do
    with {:user, %Accounts.User{} = user} <- {:user, Accounts.get_user_by_email(email)},
         {:ok, {user, _expired_tokens}} <-
           Accounts.update_user_password(user, %{password: password}) do
      {:ok, user}
    else
      {:user, nil} -> {:error, "Es gibt keinen Benutzer mit der E-Mail #{email}."}
      {:error, changeset} -> {:error, format_errors(changeset)}
    end
  end

  # Same German messages as in the web UI.
  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&HermesWeb.CoreComponents.translate_error/1)
    |> Enum.map_join("\n", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
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
