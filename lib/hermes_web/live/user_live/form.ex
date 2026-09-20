defmodule HermesWeb.UserLive.Form do
  @moduledoc """
  Creates a user. Users can never change another user's password; a forgotten
  password is reset by the operator with `bin/reset_password`.
  """
  use HermesWeb, :live_view

  alias Hermes.Accounts
  alias Hermes.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Benutzer anlegen
        <:subtitle>Das Passwort kann danach nur der neue Benutzer selbst ändern.</:subtitle>
      </.header>

      <.form for={@form} id="user-form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:email]}
          type="email"
          label="E-Mail"
          autocomplete="off"
          spellcheck="false"
          required
        />
        <.input
          field={@form[:password]}
          type="password"
          label="Erstes Passwort"
          autocomplete="new-password"
          required
        />
        <p class="text-sm text-base-content/70 -mt-1 mb-2">Mindestens 12 Zeichen.</p>

        <footer class="flex gap-2">
          <.button phx-disable-with="Speichere..." variant="primary">Speichern</.button>
          <.button navigate={~p"/users"}>Abbrechen</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Benutzer anlegen")
     |> assign(:form, to_form(Accounts.change_user_creation()))}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      Accounts.change_user_creation(%User{}, params, validate_unique: false, hash_password: false)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.create_user(params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{user.email} wurde angelegt.")
         |> push_navigate(to: ~p"/users")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
