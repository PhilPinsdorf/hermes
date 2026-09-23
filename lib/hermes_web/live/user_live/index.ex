defmodule HermesWeb.UserLive.Index do
  use HermesWeb, :live_view

  alias Hermes.Accounts
  alias HermesWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      branding={@branding}
      current_path={@current_path}
    >
      <.header>
        Benutzer
        <:subtitle>
          Wer sich an der Weboberfläche anmelden darf. Alle Benutzer haben dieselben Rechte.
        </:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/users/new"}>
            <.icon name="hero-plus" /> Benutzer anlegen
          </.button>
        </:actions>
      </.header>

      <.table id="users" rows={@streams.users}>
        <:col :let={{_id, user}} label="E-Mail">
          {user.email}
          <span :if={self?(user, @current_scope)} class="badge badge-ghost badge-sm ml-2">du</span>
        </:col>
        <:action :let={{_id, user}}>
          <.link :if={self?(user, @current_scope)} navigate={~p"/users/settings"}>
            Mein Konto
          </.link>
        </:action>
        <:action :let={{_id, user}}>
          <button
            :if={!self?(user, @current_scope)}
            type="button"
            id={"delete-user-#{user.id}"}
            phx-click={JS.push("ask_delete", value: %{id: user.id})}
            class="btn btn-xs btn-error"
          >
            Löschen
          </button>
        </:action>
      </.table>

      <.confirm_modal
        :if={@confirm_delete}
        id="confirm-delete-user"
        title="Benutzer löschen?"
        confirm="Löschen"
        on_confirm={JS.push("delete", value: %{id: @confirm_delete.id})}
        on_cancel={JS.push("cancel_delete")}
      >
        {@confirm_delete.email} kann sich danach nicht mehr anmelden.
      </.confirm_modal>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Benutzer")
     |> assign(:confirm_delete, nil)
     |> stream(:users, Accounts.list_users())}
  end

  @impl true
  def handle_event("ask_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete, Accounts.get_user!(id))}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_delete, nil)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    socket = assign(socket, :confirm_delete, nil)
    user = Accounts.get_user!(id)

    case Accounts.delete_user(user, socket.assigns.current_scope.user) do
      {:ok, {user, tokens}} ->
        UserAuth.disconnect_sessions(tokens)

        {:noreply,
         socket
         |> stream_delete(:users, user)
         |> put_flash(:info, "#{user.email} wurde gelöscht.")}

      {:error, :self} ->
        {:noreply, put_flash(socket, :error, "Du kannst dich nicht selbst löschen.")}
    end
  end

  defp self?(user, scope), do: user.id == scope.user.id
end
