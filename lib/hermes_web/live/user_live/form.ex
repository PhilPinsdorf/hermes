defmodule HermesWeb.UserLive.Form do
  @moduledoc """
  Creates a user, or sets a new password for another user (the replacement
  for "forgot password", since Hermes sends no emails).
  """
  use HermesWeb, :live_view

  alias Hermes.Accounts
  alias Hermes.Accounts.User
  alias HermesWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle :if={@live_action == :password}>
          Alle Sitzungen von {@user.email} werden danach abgemeldet.
        </:subtitle>
      </.header>

      <.form for={@form} id="user-form" phx-change="validate" phx-submit="save">
        <.input
          :if={@live_action == :new}
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
          label={if @live_action == :new, do: "Passwort", else: "Neues Passwort"}
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
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Benutzer anlegen")
    |> assign(:user, %User{})
    |> assign(:form, to_form(Accounts.change_user_creation()))
  end

  defp apply_action(socket, :password, %{"id" => id}) do
    user = Accounts.get_user!(id)

    if user.id == socket.assigns.current_scope.user.id do
      # Own password is changed in the account settings (requires re-authentication).
      push_navigate(socket, to: ~p"/users/settings")
    else
      socket
      |> assign(:page_title, "Passwort setzen")
      |> assign(:user, user)
      |> assign(:form, to_form(Accounts.change_user_password(user, %{}, hash_password: false)))
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      case socket.assigns.live_action do
        :new ->
          Accounts.change_user_creation(%User{}, params,
            validate_unique: false,
            hash_password: false
          )

        :password ->
          Accounts.change_user_password(socket.assigns.user, params, hash_password: false)
      end

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  defp save(socket, :new, params) do
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

  defp save(socket, :password, params) do
    case Accounts.update_user_password(socket.assigns.user, params) do
      {:ok, {user, expired_tokens}} ->
        UserAuth.disconnect_sessions(expired_tokens)

        {:noreply,
         socket
         |> put_flash(:info, "Passwort für #{user.email} wurde gesetzt.")
         |> push_navigate(to: ~p"/users")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
