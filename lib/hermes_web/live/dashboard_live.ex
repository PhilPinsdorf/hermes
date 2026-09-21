defmodule HermesWeb.DashboardLive do
  use HermesWeb, :live_view

  alias Hermes.Ari
  alias Hermes.Calls
  alias Hermes.Calls.CallSupervisor
  alias Hermes.Directory
  alias Hermes.Schedule
  alias Hermes.Settings
  alias Hermes.Telephony.Monitor
  alias HermesWeb.ScheduleGrid

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Übersicht
      </.header>

      <section id="pbx-status" class="flex flex-wrap items-center gap-3 text-sm">
        <span class={[
          "badge gap-1",
          (@ari_status == :connected && "badge-success") || "badge-error"
        ]}>
          <.icon
            name={if @ari_status == :connected, do: "hero-signal", else: "hero-signal-slash"}
            class="size-4"
          />
          {if @ari_status == :connected,
            do: "Telefonanlage verbunden",
            else: "Telefonanlage getrennt"}
        </span>
        <span
          :if={@ari_status == :connected}
          id="trunk-status"
          class={["badge gap-1", (@telephony.trunk == :online && "badge-success") || "badge-error"]}
        >
          <.icon name="hero-phone-arrow-up-right" class="size-4" />
          {if @telephony.trunk == :online, do: "Amt erreichbar", else: "Amt nicht erreichbar"}
        </span>
        <span :if={@active_calls > 0} id="active-calls" class="badge badge-info gap-1">
          <.icon name="hero-phone" class="size-4" />
          {running_calls_label(@active_calls)}
        </span>
        <span :if={!@telephony.ready?} class="text-base-content/70">
          <%= if @ari_status != :connected do %>
            Ohne Verbindung zur Telefonanlage nimmt Hermes keine Anrufe an.
          <% else %>
            Die Fritz!Box antwortet nicht – siehe <code>docs/fritzbox.md</code>.
          <% end %>
        </span>
      </section>

      <section id="on-duty" class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title">Jetzt im Dienst</h2>

          <%= if @status.on_duty == [] do %>
            <p id="on-duty-none" class="text-warning">
              <.icon name="hero-exclamation-triangle" class="size-5" />
              Niemand – Anrufer hören die Ansage.
            </p>
          <% else %>
            <ol id="on-duty-list" class="list-decimal list-inside space-y-1">
              <li :for={person <- @status.on_duty} id={"on-duty-#{person.id}"}>
                <span class="font-semibold">{person.name}</span>
              </li>
            </ol>
            <p :if={length(@status.on_duty) > 1} class="text-sm text-base-content/70">
              Angerufen wird in dieser Reihenfolge.
            </p>
          <% end %>

          <div id="next-change" class="mt-2 text-sm">
            <%= case @status.next_change do %>
              <% nil -> %>
                <span class="text-base-content/70">
                  In den nächsten 7 Tagen ändert sich nichts.
                </span>
              <% {at, people} -> %>
                <span class="text-base-content/70">Nächster Wechsel</span>
                <span class="font-semibold">{format_change_time(at)}</span>
                <span>
                  → {if people == [], do: "niemand", else: Enum.map_join(people, ", ", & &1.name)}
                </span>
            <% end %>
          </div>
        </div>
      </section>

      <section :if={!@setup_done?} id="setup-checklist" class="card bg-base-200">
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
            <.check done={@shift_count > 0} id="check-shifts">
              Schichten im Wochenplan eintragen –
              <.link navigate={~p"/schedule"} class="link">Wochenplan</.link>
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
    if connected?(socket) do
      Directory.subscribe()
      Schedule.subscribe()
      Ari.subscribe()
      Calls.subscribe()
      Monitor.subscribe()
      schedule_tick()
    end

    {:ok,
     socket
     |> assign(:page_title, "Übersicht")
     |> assign(:setting, Settings.get())
     |> load()}
  end

  @impl true
  def handle_info({:ari_status, status}, socket),
    do: {:noreply, assign(socket, :ari_status, status)}

  def handle_info({:telephony_status, status}, socket),
    do: {:noreply, assign(socket, :telephony, status)}

  def handle_info({event, _id}, socket)
      when event in [:call_started, :call_ended, :call_bridged, :call_logged] do
    {:noreply, assign(socket, :active_calls, CallSupervisor.count_calls())}
  end

  def handle_info({:person_changed, _}, socket), do: {:noreply, load(socket)}
  def handle_info({:schedule_changed, _}, socket), do: {:noreply, load(socket)}

  # Re-resolve regularly, so a shift change shows up without a page reload.
  def handle_info(:tick, socket) do
    schedule_tick()
    {:noreply, load(socket)}
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, :timer.seconds(30))

  defp running_calls_label(1), do: "1 laufender Anruf"
  defp running_calls_label(count), do: "#{count} laufende Anrufe"

  defp load(socket) do
    people = Directory.list_people()
    shift_count = length(Schedule.list_shifts())
    active_people = Enum.count(people, & &1.active)
    setting = socket.assigns.setting

    socket
    |> assign(:status, Schedule.status())
    |> assign(:ari_status, Ari.status())
    |> assign(:telephony, Monitor.status())
    |> assign(:active_calls, CallSupervisor.count_calls())
    |> assign(:active_people, active_people)
    |> assign(:shift_count, shift_count)
    |> assign(:setup_done?, setting.clip_number != nil and active_people > 0 and shift_count > 0)
  end

  defp format_change_time(%DateTime{} = at) do
    local = Schedule.local_naive(at)
    today = DateTime.utc_now() |> Schedule.local_naive() |> NaiveDateTime.to_date()
    time = Calendar.strftime(local, "%H:%M")

    case Date.diff(NaiveDateTime.to_date(local), today) do
      0 ->
        "heute #{time}"

      1 ->
        "morgen #{time}"

      _ ->
        Calendar.strftime(local, "%a %d.%m. %H:%M",
          abbreviated_day_of_week_names: &ScheduleGrid.day_abbr/1
        )
    end
  end
end
