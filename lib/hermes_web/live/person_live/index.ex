defmodule HermesWeb.PersonLive.Index do
  use HermesWeb, :live_view

  alias Hermes.Directory
  alias Hermes.Directory.PhoneNumber
  alias Hermes.Settings

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
        Personen
        <:subtitle>Wer Anrufe übernehmen kann. Die Handynummern sieht kein Anrufer.</:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/people/new"}>
            <.icon name="hero-plus" /> Person anlegen
          </.button>
        </:actions>
      </.header>

      <p :if={@people == []} id="people-empty" class="text-base-content/70">
        Noch keine Personen angelegt.
      </p>

      <%!-- Phones: one card per person, the name first. --%>
      <ul :if={@people != []} id="people-cards" class="sm:hidden space-y-2">
        <li :for={person <- @people} id={"person-card-#{person.id}"} class="card card-body gap-1 p-4">
          <div class="flex items-center gap-2">
            <h2 class={["text-lg font-semibold leading-tight", !person.active && "opacity-50"]}>
              {person.name}
            </h2>
            <span :if={!person.active} class="badge badge-ghost badge-sm">inaktiv</span>
          </div>

          <p class="text-base tabular-nums">{PhoneNumber.format(person.phone_e164)}</p>
          <p class="text-sm text-base-content/60">
            Klingeldauer: {ring_timeout(person, @default_ring_timeout)}
          </p>

          <div class="pt-2">
            <.link navigate={~p"/people/#{person}/edit"} class="btn btn-primary btn-sm w-full">
              Bearbeiten
            </.link>
          </div>
        </li>
      </ul>

      <div :if={@people != []} class="hidden sm:block">
        <.table id="people" rows={@people} row_id={&"people-#{&1.id}"}>
          <:col :let={person} label="Name">
            <span class={!person.active && "opacity-50"}>{person.name}</span>
            <span :if={!person.active} class="badge badge-ghost badge-sm ml-2">inaktiv</span>
          </:col>
          <:col :let={person} label="Handy">{PhoneNumber.format(person.phone_e164)}</:col>
          <:col :let={person} label="Klingeldauer">
            {ring_timeout(person, @default_ring_timeout)}
          </:col>
          <:action :let={person}>
            <.link navigate={~p"/people/#{person}/edit"} class="btn btn-primary btn-xs">
              Bearbeiten
            </.link>
          </:action>
        </.table>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Directory.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Personen")
     |> assign(:default_ring_timeout, Settings.get().ring_timeout_seconds)
     |> load_people()}
  end

  @impl true
  def handle_info({:person_changed, _person}, socket) do
    {:noreply, load_people(socket)}
  end

  # "25 s" for an override, otherwise the global default is named explicitly —
  # a card has no column header that could explain "Standard".
  defp ring_timeout(%{ring_timeout_seconds: nil}, default), do: "#{default} s (Standard)"
  defp ring_timeout(%{ring_timeout_seconds: seconds}, _default), do: "#{seconds} s"

  defp load_people(socket) do
    assign(socket, :people, Directory.list_people())
  end
end
