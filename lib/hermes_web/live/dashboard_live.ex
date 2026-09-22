defmodule HermesWeb.DashboardLive do
  @moduledoc """
  The overview answers three questions, in this order:

    1. Are calls being forwarded at all right now?
    2. Who gets them, and until when?
    3. Is the technology behind it healthy?

  Everything else (setup steps, the last calls) comes after that.
  """
  use HermesWeb, :live_view

  alias Hermes.Ari
  alias Hermes.Calls
  alias Hermes.Calls.{CallSupervisor, Log}
  alias Hermes.Directory
  alias Hermes.Schedule
  alias Hermes.Settings
  alias Hermes.Telephony.Monitor
  alias HermesWeb.CallLive.Labels
  alias HermesWeb.ScheduleGrid

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      branding={@branding}
      current_path={@current_path}
    >
      <%!-- 1. The state of the whole thing, plus the switch for it. --%>
      <section
        id="forwarding"
        class={[
          "card card-body gap-4 border-l-4",
          (@setting.forwarding_enabled && "border-l-success") || "border-l-warning"
        ]}
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-xl font-semibold tracking-tight">
              {if @setting.forwarding_enabled,
                do: "Weiterleitung läuft",
                else: "Weiterleitung pausiert"}
            </h1>
            <p id="forwarding-explanation" class="text-sm text-base-content/70 mt-1">
              {forwarding_explanation(assigns)}
            </p>
          </div>

          <label class="flex shrink-0 cursor-pointer items-center gap-2">
            <span class="text-sm text-base-content/70 hidden sm:inline">
              {if @setting.forwarding_enabled, do: "An", else: "Aus"}
            </span>
            <input
              type="checkbox"
              id="forwarding-switch"
              class="toggle toggle-success"
              checked={@setting.forwarding_enabled}
              phx-click="toggle_forwarding"
              aria-label="Weiterleitung ein- oder ausschalten"
            />
          </label>
        </div>

        <div :if={@active_calls > 0} id="active-calls" class="flex items-center gap-2 text-sm">
          <span class="badge badge-info">{running_calls_label(@active_calls)}</span>
          <.link navigate={~p"/calls"} class="link">ansehen</.link>
        </div>
      </section>

      <%!-- 2. Who is on duty. --%>
      <section id="on-duty" class="card card-body gap-3">
        <div class="flex items-baseline justify-between gap-2">
          <h2 class="font-semibold">Jetzt im Dienst</h2>
          <.link navigate={~p"/schedule"} class="link text-sm">Wochenplan</.link>
        </div>

        <%= cond do %>
          <% !@setting.forwarding_enabled -> %>
            <p id="on-duty-paused" class="text-base-content/70">
              Während der Pause wird niemand angerufen.
            </p>
          <% @status.on_duty == [] -> %>
            <p id="on-duty-none" class="flex items-center gap-2 text-warning">
              <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
              Niemand – Anrufer hören die Ansage.
            </p>
          <% true -> %>
            <ol id="on-duty-list" class="space-y-2">
              <li
                :for={{person, index} <- Enum.with_index(@status.on_duty, 1)}
                id={"on-duty-#{person.id}"}
                class="flex items-center gap-3"
              >
                <span class="flex size-7 shrink-0 items-center justify-center rounded-full bg-base-200 text-sm tabular-nums">
                  {index}
                </span>
                <span class="font-medium">{person.name}</span>
              </li>
            </ol>
            <p :if={length(@status.on_duty) > 1} class="text-sm text-base-content/60">
              Ungefähr in dieser Reihenfolge wird angerufen – bei gleicher Reihenfolge im
              Wochenplan entscheidet bei jedem Anruf das Los.
            </p>
        <% end %>

        <%!-- HEEx drops the newlines between the spans, so the gap between the
              words comes from the layout rather than from whitespace. --%>
        <div
          id="next-change"
          class="flex flex-wrap items-baseline gap-x-1 border-t border-base-300 pt-3 text-sm"
        >
          <%= case @status.next_change do %>
            <% nil -> %>
              <span class="text-base-content/60">
                In den nächsten sieben Tagen ändert sich nichts.
              </span>
            <% {at, people} -> %>
              <span class="text-base-content/60">Nächster Wechsel</span>
              <span class="font-medium">{format_change_time(at)}</span>
              <span class="text-base-content/60">→</span>
              <span>
                {if people == [], do: "niemand", else: Enum.map_join(people, ", ", & &1.name)}
              </span>
          <% end %>
        </div>
      </section>

      <%!-- 3. The technology, in plain words. --%>
      <section id="system" class="card card-body gap-3">
        <div class="flex items-baseline justify-between gap-2">
          <h2 class="font-semibold">Technik</h2>
          <.link navigate={~p"/system"} class="link text-sm">Details</.link>
        </div>

        <ul class="space-y-2 text-sm">
          <.status_row
            id="status-ari"
            ok?={@telephony.ari == :connected}
            label="Telefonanlage"
            ok_text="verbunden"
            problem_text="nicht erreichbar"
            hint="Hermes steuert die Anlage, die im selben Container-Verbund läuft."
          />
          <.status_row
            id="status-trunk"
            ok?={@telephony.trunk == :online}
            label="Fritz!Box"
            ok_text="antwortet"
            problem_text="antwortet nicht"
            hint="Über sie kommen Anrufe herein und gehen Anrufe zum Handy hinaus."
          />
        </ul>

        <p :if={!@telephony.ready?} class="text-sm text-warning">
          Solange das so ist, können Anrufe nicht weitergeleitet werden.
        </p>
      </section>

      <%!-- What is still missing to get going. --%>
      <section :if={!@setup_done?} id="setup-checklist" class="card card-body gap-3">
        <h2 class="font-semibold">Einrichtung</h2>
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
        <p class="text-sm text-base-content/60">
          Danach die Kontakt-Datei aus den Einstellungen an alle Personen verteilen.
        </p>
      </section>

      <%!-- A glance at what actually happened. --%>
      <section :if={@recent_calls != []} id="recent-calls" class="card card-body gap-3">
        <div class="flex items-baseline justify-between gap-2">
          <h2 class="font-semibold">Letzte Anrufe</h2>
          <.link navigate={~p"/calls"} class="link text-sm">Alle</.link>
        </div>

        <ul class="divide-y divide-base-300">
          <li
            :for={call <- @recent_calls}
            id={"recent-call-#{call.id}"}
            class="flex items-center gap-3 py-2 text-sm"
          >
            <span class="text-base-content/60 tabular-nums">
              {format_short_time(call.started_at)}
            </span>
            <span class="truncate">
              {Hermes.Directory.PhoneNumber.format(call.caller_number) || "unbekannt"}
            </span>
            <span class={["badge badge-sm ml-auto shrink-0", Labels.result_class(call.result)]}>
              {Labels.result(call.result)}
            </span>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :ok?, :boolean, required: true
  attr :label, :string, required: true
  attr :ok_text, :string, required: true
  attr :problem_text, :string, required: true
  attr :hint, :string, required: true

  defp status_row(assigns) do
    ~H"""
    <li id={@id} class="flex items-start gap-2" data-ok={to_string(@ok?)}>
      <.icon
        name={if @ok?, do: "hero-check-circle", else: "hero-exclamation-circle"}
        class={["size-5 shrink-0", (@ok? && "text-success") || "text-error"]}
      />
      <span>
        <span class="font-medium">{@label}</span>
        {if @ok?, do: @ok_text, else: @problem_text}
        <span class="block text-base-content/60">{@hint}</span>
      </span>
    </li>
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
      Settings.subscribe()
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
  def handle_event("toggle_forwarding", _params, socket) do
    enabled? = !socket.assigns.setting.forwarding_enabled
    {:ok, setting} = Settings.set_forwarding(enabled?)

    message =
      if enabled?,
        do: "Weiterleitung läuft wieder.",
        else: "Weiterleitung pausiert – Anrufer hören ab sofort die Ansage."

    {:noreply, socket |> assign(:setting, setting) |> load() |> put_flash(:info, message)}
  end

  @impl true
  def handle_info({:settings_changed, setting}, socket) do
    {:noreply, socket |> assign(:setting, setting) |> load()}
  end

  def handle_info({:telephony_status, status}, socket),
    do: {:noreply, assign(socket, :telephony, status)}

  def handle_info({:ari_status, _status}, socket),
    do: {:noreply, assign(socket, :telephony, Monitor.status())}

  def handle_info({event, _id}, socket)
      when event in [:call_started, :call_ended, :call_bridged, :call_logged] do
    {:noreply,
     socket
     |> assign(:active_calls, CallSupervisor.count_calls())
     |> assign(:recent_calls, Log.list_calls(%{limit: 5}))}
  end

  def handle_info({:person_changed, _}, socket), do: {:noreply, load(socket)}
  def handle_info({:schedule_changed, _}, socket), do: {:noreply, load(socket)}

  # Re-resolve regularly, so a shift change shows up without a page reload.
  def handle_info(:tick, socket) do
    schedule_tick()
    {:noreply, load(socket)}
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, :timer.seconds(30))

  defp load(socket) do
    people = Directory.list_people()
    shift_count = length(Schedule.list_shifts())
    active_people = Enum.count(people, & &1.active)
    setting = socket.assigns.setting

    socket
    |> assign(:status, Schedule.status())
    |> assign(:telephony, Monitor.status())
    |> assign(:active_calls, CallSupervisor.count_calls())
    |> assign(:recent_calls, Log.list_calls(%{limit: 5}))
    |> assign(:active_people, active_people)
    |> assign(:shift_count, shift_count)
    |> assign(:setup_done?, setting.clip_number != nil and active_people > 0 and shift_count > 0)
  end

  # One sentence that says what happens to the next caller.
  defp forwarding_explanation(%{setting: %{forwarding_enabled: false}} = assigns) do
    case assigns.setting.forwarding_paused_at do
      %DateTime{} = at -> "Seit #{format_change_time(at)}. Anrufer hören die Ansage."
      _ -> "Anrufer hören die Ansage, es klingelt kein Telefon."
    end
  end

  defp forwarding_explanation(%{telephony: %{ready?: false}}),
    do: "Achtung: Die Technik meldet ein Problem, siehe unten."

  defp forwarding_explanation(%{status: %{on_duty: []}}),
    do: "Gerade hat niemand Dienst – Anrufer hören die Ansage."

  defp forwarding_explanation(%{status: %{on_duty: [person]}}),
    do: "Anrufe gehen an #{person.name}."

  defp forwarding_explanation(%{status: %{on_duty: [first | rest]}}),
    do: "Anrufe gehen an #{first.name}, sonst an #{Enum.map_join(rest, ", ", & &1.name)}."

  defp running_calls_label(1), do: "1 laufender Anruf"
  defp running_calls_label(count), do: "#{count} laufende Anrufe"

  defp format_change_time(%DateTime{} = at) do
    local = Schedule.local_naive(at)
    today = DateTime.utc_now() |> Schedule.local_naive() |> NaiveDateTime.to_date()
    time = Calendar.strftime(local, "%H:%M")

    case Date.diff(NaiveDateTime.to_date(local), today) do
      0 ->
        "heute #{time}"

      1 ->
        "morgen #{time}"

      -1 ->
        "gestern #{time}"

      _ ->
        Calendar.strftime(local, "%a %d.%m. %H:%M",
          abbreviated_day_of_week_names: &ScheduleGrid.day_abbr/1
        )
    end
  end

  defp format_short_time(%DateTime{} = at) do
    local = Schedule.local_naive(at)
    today = DateTime.utc_now() |> Schedule.local_naive() |> NaiveDateTime.to_date()

    if NaiveDateTime.to_date(local) == today do
      Calendar.strftime(local, "%H:%M")
    else
      Calendar.strftime(local, "%d.%m. %H:%M")
    end
  end
end
