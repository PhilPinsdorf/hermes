defmodule HermesWeb.PersonLive.Form do
  use HermesWeb, :live_view

  alias Hermes.Directory
  alias Hermes.Directory.Person
  alias Hermes.Settings

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
      </.header>

      <.form for={@form} id="person-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" required />
        <.input
          field={@form[:phone_e164]}
          type="tel"
          label="Handynummer"
          placeholder="0171 1234567"
          autocomplete="off"
          required
        />
        <p class="text-sm text-base-content/70 -mt-1 mb-2">
          Auch eine interne Nebenstelle der Fritz!Box ist möglich, z. B. <code>**621</code>
          für ein Tischtelefon oder ein Softphone im selben Netz.
        </p>
        <.input
          field={@form[:ring_timeout_seconds]}
          type="number"
          label="Klingeldauer in Sekunden (optional)"
          placeholder={"Standard: #{@default_ring_timeout} s"}
          min="5"
          max="120"
        />
        <.input field={@form[:active]} type="checkbox" label="Aktiv (kann Dienst haben)" />
        <.input field={@form[:notes]} type="textarea" label="Notizen" />

        <footer class="flex gap-2">
          <.button phx-disable-with="Speichere..." variant="primary">Speichern</.button>
          <.button navigate={~p"/people"}>Abbrechen</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:default_ring_timeout, Settings.get().ring_timeout_seconds)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    person = Directory.get_person!(id)

    socket
    |> assign(:page_title, "Person bearbeiten")
    |> assign(:person, person)
    |> assign(:form, to_form(Directory.change_person(person)))
  end

  defp apply_action(socket, :new, _params) do
    person = %Person{}

    socket
    |> assign(:page_title, "Person anlegen")
    |> assign(:person, person)
    |> assign(:form, to_form(Directory.change_person(person)))
  end

  @impl true
  def handle_event("validate", %{"person" => person_params}, socket) do
    changeset = Directory.change_person(socket.assigns.person, person_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"person" => person_params}, socket) do
    save_person(socket, socket.assigns.live_action, person_params)
  end

  defp save_person(socket, :edit, person_params) do
    case Directory.update_person(socket.assigns.person, person_params) do
      {:ok, _person} ->
        {:noreply,
         socket
         |> put_flash(:info, "Person gespeichert.")
         |> push_navigate(to: ~p"/people")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_person(socket, :new, person_params) do
    case Directory.create_person(person_params) do
      {:ok, _person} ->
        {:noreply,
         socket
         |> put_flash(:info, "Person angelegt.")
         |> push_navigate(to: ~p"/people")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
