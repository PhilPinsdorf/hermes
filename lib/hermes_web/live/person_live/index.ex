defmodule HermesWeb.PersonLive.Index do
  use HermesWeb, :live_view

  alias Hermes.Directory
  alias Hermes.Directory.PhoneNumber

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Personen
        <:subtitle>Wer Anrufe übernehmen kann. Die Handynummern sieht kein Anrufer.</:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/people/new"}>
            <.icon name="hero-plus" /> Person anlegen
          </.button>
        </:actions>
      </.header>

      <p :if={@empty?} id="people-empty" class="text-base-content/70">
        Noch keine Personen angelegt.
      </p>

      <.table :if={!@empty?} id="people" rows={@streams.people}>
        <:col :let={{_id, person}} label="Name">
          <span class={!person.active && "opacity-50"}>{person.name}</span>
          <span :if={!person.active} class="badge badge-ghost badge-sm ml-2">inaktiv</span>
        </:col>
        <:col :let={{_id, person}} label="Handy">{PhoneNumber.format(person.phone_e164)}</:col>
        <:col :let={{_id, person}} label="Klingeldauer">
          <%= if person.ring_timeout_seconds do %>
            {person.ring_timeout_seconds} s
          <% else %>
            <span class="text-base-content/50">Standard</span>
          <% end %>
        </:col>
        <:action :let={{_id, person}}>
          <.link navigate={~p"/people/#{person}/edit"}>Bearbeiten</.link>
        </:action>
        <:action :let={{id, person}}>
          <.link
            phx-click={JS.push("delete", value: %{id: person.id}) |> hide("##{id}")}
            data-confirm={"#{person.name} wirklich löschen?"}
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
    if connected?(socket), do: Directory.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Personen")
     |> load_people()}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    person = Directory.get_person!(id)
    {:ok, _} = Directory.delete_person(person)

    {:noreply, socket |> put_flash(:info, "#{person.name} wurde gelöscht.") |> load_people()}
  end

  @impl true
  def handle_info({:person_changed, _person}, socket) do
    {:noreply, load_people(socket)}
  end

  defp load_people(socket) do
    people = Directory.list_people()

    socket
    |> assign(:empty?, people == [])
    |> stream(:people, people, reset: true)
  end
end
