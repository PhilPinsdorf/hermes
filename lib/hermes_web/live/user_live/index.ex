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
        <:action :let={{id, user}}>
          <.link
            :if={!self?(user, @current_scope)}
            phx-click={JS.push("delete", value: %{id: user.id}) |> hide("##{id}")}
            data-confirm={"#{user.email} wirklich löschen?"}
          >
            Löschen
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Benutzer")
     |> stream(:users, Accounts.list_users())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
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
