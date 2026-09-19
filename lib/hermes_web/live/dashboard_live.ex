defmodule HermesWeb.DashboardLive do
  use HermesWeb, :live_view

  alias Hermes.Directory
  alias Hermes.Settings

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Übersicht
        <:subtitle>Wer gerade Dienst hat, erscheint hier, sobald der Wochenplan steht.</:subtitle>
      </.header>

      <section id="setup-checklist" class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title">Einrichtung</h2>
          <ul class="space-y-2">
            <.check done={@setting.clip_number != nil} id="check-clip">
              Angezeigte Rufnummer festlegen –
              <.link navigate={~p"/settings"} class="link">Einstellungen</.link>
            </.check>
            <.check done={@active_people > 0} id="check-people">
              Mindestens eine aktive Person anlegen –
              <.link navigate={~p"/people"} class="link">Personen</.link>
              <span :if={@active_people > 0} class="text-base-content/60">
                ({@active_people} aktiv)
              </span>
            </.check>
          </ul>
          <p class="text-sm text-base-content/70 mt-2">
            Danach die Kontakt-Datei aus den Einstellungen an alle Personen verteilen.
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :done, :boolean, required: true
  attr :id, :string, required: true
  slot :inner_block, required: true

  defp check(assigns) do
    ~H"""
    <li id={@id} class="flex items-start gap-2" data-done={to_string(@done)}>
      <.icon
        name={if @done, do: "hero-check-circle", else: "hero-ellipsis-horizontal-circle"}
        class={["size-5 shrink-0", (@done && "text-success") || "text-base-content/40"]}
      />
      <span>{render_slot(@inner_block)}</span>
    </li>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Directory.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Übersicht")
     |> assign(:setting, Settings.get())
     |> assign_people()}
  end

  @impl true
  def handle_info({:person_changed, _person}, socket) do
    {:noreply, assign_people(socket)}
  end

  defp assign_people(socket) do
    assign(socket, :active_people, Enum.count(Directory.list_people(), & &1.active))
  end
end
