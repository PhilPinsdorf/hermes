defmodule HermesWeb.ScheduleLive do
  @moduledoc """
  The weekly plan: a 7-column grid in 30-minute rows. Drag in a day column to
  create a shift, click a shift to edit it. Shifts past midnight continue in
  the next day's column.

  One-off exceptions (holidays, sick leave, swaps) are listed right below the
  plan they override, and are added through the same kind of dialog as shifts.
  """
  use HermesWeb, :live_view

  alias Hermes.Directory
  alias Hermes.Schedule
  alias Hermes.Schedule.{Override, Shift}
  alias HermesWeb.ScheduleGrid

  @kind_labels %{
    add: "Im Dienst (Vertretung / zusätzlich)",
    block: "Abwesend (Urlaub, krank …)"
  }

  # One horizontal line per hour (the column is 60rem = 24 × 2.5rem tall).
  @hour_lines "background-image: repeating-linear-gradient(to bottom, transparent 0, " <>
                "transparent calc(2.5rem - 1px), var(--color-base-300) calc(2.5rem - 1px), " <>
                "var(--color-base-300) 2.5rem);"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      branding={@branding}
      current_path={@current_path}
      wide
    >
      <.header>
        Wochenplan
        <:subtitle>
          <span class="hidden sm:inline">
            In einer Tagesspalte ziehen, um eine Schicht anzulegen; auf eine Schicht tippen, um
            sie zu bearbeiten.
          </span>
          <span class="sm:hidden">Auf eine Schicht tippen, um sie zu bearbeiten.</span>
          Einmalige Ausnahmen wie Urlaub oder Tausch stehen unter dem Plan.
        </:subtitle>
        <:actions>
          <div class="flex flex-wrap justify-end gap-2">
            <.button patch={~p"/schedule/overrides/new"}>
              <.icon name="hero-plus-bold" /> Ausnahme anlegen
            </.button>
            <.button variant="primary" patch={~p"/schedule/shifts/new"}>
              <.icon name="hero-plus-bold" /> Schicht anlegen
            </.button>
          </div>
        </:actions>
      </.header>

      <section id="priority-rules" class="card card-body gap-2 py-3">
        <h2 class="text-sm font-semibold">Wer wird zuerst angerufen?</h2>
        <ul class="space-y-1 text-sm text-base-content/70">
          <li class="flex gap-2">
            <span class="text-base-content/40">1.</span>
            <span>
              Wer gerade Dienst hat, wird nach <strong>Priorität</strong> gerufen — die
              kleinere Zahl zuerst. Sie steht unter jeder Schicht.
            </span>
          </li>
          <li class="flex gap-2">
            <span class="text-base-content/40">2.</span>
            <span>
              Bei <strong>gleicher Priorität</strong> entscheidet das Los, damit nicht immer
              dieselbe Person als Erste klingelt.
            </span>
          </li>
          <li class="flex gap-2">
            <span class="text-base-content/40">3.</span>
            <span>
              <strong>Ausnahmen</strong> (Vertretungen) kommen nach allen Schichten dran.
            </span>
          </li>
        </ul>
        <p class="text-sm text-base-content/60">
          Nimmt jemand nicht ab oder gibt mit der Taste 2 weiter, ist die nächste Person dran.
        </p>
      </section>

      <div :if={@people != []} id="legend" class="flex flex-wrap gap-2 text-sm">
        <span
          :for={person <- @people}
          class={["person-chip", !person.active && "opacity-50"]}
          style={ScheduleGrid.person_color_style(person)}
        >
          {person.name}
        </span>
      </div>

      <div class="hidden sm:block overflow-x-auto">
        <div class="min-w-[44rem]">
          <div class="grid grid-cols-[3rem_repeat(7,1fr)] text-sm font-semibold text-center">
            <div></div>
            <div :for={day <- 1..7} class={["py-1", day == @now_day && "text-primary"]}>
              {ScheduleGrid.day_abbr(day)}
            </div>
          </div>

          <div
            id="schedule-grid"
            phx-hook=".ShiftGrid"
            class="grid grid-cols-[3rem_repeat(7,1fr)] select-none"
          >
            <div class="relative" style="height: 60rem">
              <div
                :for={hour <- 0..23}
                class="absolute right-1 text-xs text-base-content/50 -translate-y-1/2"
                style={"top: #{hour / 24 * 100}%"}
              >
                {if hour > 0, do: ScheduleGrid.format_minutes(hour * 60)}
              </div>
            </div>

            <div
              :for={day <- 1..7}
              id={"day-#{day}"}
              data-day={day}
              class={[
                "relative border-l border-base-300 cursor-crosshair",
                day == @now_day && "bg-base-200/60"
              ]}
              style={"height: 60rem; #{@hour_lines}"}
            >
              <.link
                :for={seg <- @grid[day]}
                id={"shift-#{seg.shift.id}-#{seg.day}"}
                data-shift={seg.shift.id}
                patch={~p"/schedule/shifts/#{seg.shift.id}/edit"}
                class={[
                  "absolute overflow-hidden border-l-4 px-1 text-xs leading-tight cursor-pointer",
                  "hover:brightness-110 hover:z-10",
                  seg.continued? && "rounded-b",
                  seg.continues? && "rounded-t",
                  !seg.continued? && !seg.continues? && "rounded",
                  !seg.shift.active && "opacity-40 border-dashed"
                ]}
                style={ScheduleGrid.segment_style(seg)}
                title={shift_title(seg.shift)}
              >
                <span class="block font-semibold">{seg.shift.person.name}</span>
                <span :if={!seg.continued?} class="block opacity-70">
                  {ScheduleGrid.format_time(seg.shift.starts_at)}–{ScheduleGrid.format_time(
                    seg.shift.ends_at
                  )}
                </span>
                <span :if={seg.continued?} class="block opacity-70">
                  ↳ bis {ScheduleGrid.format_time(seg.shift.ends_at)}
                </span>
                <span :if={!seg.continued?} class="block opacity-70 tabular-nums">
                  Priorität {seg.shift.position}
                </span>
              </.link>

              <div
                :if={day == @now_day}
                id="now-marker"
                class="absolute inset-x-0 border-t-2 border-error z-20 pointer-events-none"
                style={"top: #{@now_minute / 1440 * 100}%"}
              >
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Phones get a list per day instead of seven columns side by side. --%>
      <div class="sm:hidden space-y-3" id="schedule-days">
        <section :for={day <- 1..7} id={"day-list-#{day}"}>
          <h2 class={[
            "text-sm font-semibold mb-1",
            (day == @now_day && "text-primary") || "text-base-content/70"
          ]}>
            {ScheduleGrid.day_name(day)}
            <span :if={day == @now_day} class="font-normal">· heute</span>
          </h2>

          <p :if={@grid[day] == []} class="text-sm text-base-content/50">frei</p>

          <ul class="space-y-1">
            <%= for seg <- @grid[day] do %>
              <li :if={!seg.continued?}>
                <.link
                  patch={~p"/schedule/shifts/#{seg.shift.id}/edit"}
                  class={[
                    "block rounded border border-l-4 px-3 py-2",
                    !seg.shift.active && "opacity-50 border-dashed"
                  ]}
                  style={ScheduleGrid.person_color_style(seg.shift.person)}
                >
                  <span class="flex items-center gap-3">
                    <span class="font-medium">{seg.shift.person.name}</span>
                    <span class="ml-auto text-sm tabular-nums">
                      {ScheduleGrid.format_time(seg.shift.starts_at)}–{ScheduleGrid.format_time(
                        seg.shift.ends_at
                      )}
                    </span>
                  </span>
                  <span class="block text-sm text-base-content/60 tabular-nums">
                    Priorität {seg.shift.position}
                  </span>
                </.link>
              </li>
              <li :if={seg.continued?} class="px-3 py-1 text-sm text-base-content/60">
                ↳ aus der Nacht: {seg.shift.person.name} bis {ScheduleGrid.format_time(
                  seg.shift.ends_at
                )}
              </li>
            <% end %>
          </ul>
        </section>
      </div>

      <%!-- Exceptions belong right under the plan they override. --%>
      <section id="overrides" class="card">
        <div class="card-body gap-3">
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="text-lg font-semibold tracking-tight">Ausnahmen</h2>
            <p class="text-sm text-base-content/70">
              Gehen dem Wochenplan vor. Für einen Tausch: die eine Person als abwesend, die
              andere als im Dienst eintragen.
            </p>
          </div>

          <p :if={@overrides == []} id="overrides-empty" class="text-sm text-base-content/70">
            Keine aktuellen oder geplanten Ausnahmen.
          </p>

          <ul :if={@overrides != []} class="divide-y divide-base-300 -mb-2">
            <li
              :for={override <- @overrides}
              id={"override-#{override.id}"}
              class="py-3 sm:flex sm:items-center sm:gap-x-3 sm:py-2"
            >
              <div class="flex items-center gap-2">
                <%!-- Without this one has to read every date to see what is in
                      force right now. --%>
                <span class={[
                  "badge badge-sm",
                  (Override.state(override, @now) == :running && "badge-info") || "badge-ghost"
                ]}>
                  {if Override.state(override, @now) == :running, do: "läuft", else: "geplant"}
                </span>
                <span class={[
                  "badge badge-sm",
                  (override.kind == :block && "badge-warning") || "badge-success"
                ]}>
                  {if override.kind == :block, do: "abwesend", else: "im Dienst"}
                </span>
                <span class="font-medium">{override.person.name}</span>
              </div>

              <div class="mt-1 text-sm text-base-content/70 sm:mt-0 sm:flex sm:items-center sm:gap-3">
                <span class="block tabular-nums sm:inline">
                  {format_naive(override.starts_at)} – {format_naive(override.ends_at)}
                </span>
                <span :if={override.note not in [nil, ""]} class="block sm:inline">
                  {override.note}
                </span>
              </div>

              <button
                type="button"
                id={"delete-override-#{override.id}"}
                phx-click={JS.push("ask_delete_override", value: %{id: override.id})}
                class="btn btn-error btn-sm mt-3 w-full sm:btn-xs sm:mt-0 sm:ml-auto sm:w-auto"
              >
                Löschen
              </button>
            </li>
          </ul>
        </div>
      </section>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ShiftGrid">
        export default {
          mounted() {
            const SLOTS = 48
            this.el.addEventListener("pointerdown", (e) => {
              if (e.button !== 0 || e.target.closest("[data-shift]")) return
              const col = e.target.closest("[data-day]")
              if (!col) return
              e.preventDefault()

              const rect = col.getBoundingClientRect()
              const slotAt = (y) =>
                Math.max(0, Math.min(SLOTS - 1, Math.floor(((y - rect.top) / rect.height) * SLOTS)))
              const start = slotAt(e.clientY)
              let end = start

              const sel = document.createElement("div")
              sel.className = "absolute inset-x-0 bg-primary/30 border-2 border-primary rounded pointer-events-none z-30"
              col.appendChild(sel)
              const range = () => [Math.min(start, end), Math.max(start, end) + 1]
              const draw = () => {
                const [a, b] = range()
                sel.style.top = (a / SLOTS) * 100 + "%"
                sel.style.height = ((b - a) / SLOTS) * 100 + "%"
              }
              draw()

              const move = (ev) => { end = slotAt(ev.clientY); draw() }
              const up = () => {
                window.removeEventListener("pointermove", move)
                window.removeEventListener("pointerup", up)
                sel.remove()
                const [a, b] = range()
                this.pushEvent("select_range", {day: Number(col.dataset.day), from: a * 30, to: b * 30})
              }
              window.addEventListener("pointermove", move)
              window.addEventListener("pointerup", up)
            })
          }
        }
      </script>

      <div
        :if={@live_action in [:new, :edit]}
        id="shift-modal"
        class="modal modal-open modal-bottom sm:modal-middle"
      >
        <div class="modal-box">
          <h3 class="text-lg font-semibold mb-2">
            {if @live_action == :new, do: "Schicht anlegen", else: "Schicht bearbeiten"}
          </h3>

          <%= if @people == [] do %>
            <p>
              Zuerst eine Person anlegen:
              <.link navigate={~p"/people/new"} class="link">Person anlegen</.link>
            </p>
            <div class="modal-action">
              <.button patch={~p"/schedule"}>Schließen</.button>
            </div>
          <% else %>
            <.form for={@form} id="shift-form" phx-change="validate" phx-submit="save">
              <.input
                field={@form[:person_id]}
                type="select"
                label="Person"
                options={person_options(@people)}
                prompt="Bitte wählen"
                required
              />
              <.input
                field={@form[:day_of_week]}
                type="select"
                label="Wochentag"
                options={for d <- 1..7, do: {ScheduleGrid.day_name(d), d}}
              />
              <div class="grid grid-cols-2 gap-2">
                <.input field={@form[:starts_at]} type="time" label="Beginn" required />
                <.input field={@form[:ends_at]} type="time" label="Ende" required />
              </div>
              <p :if={overnight_hint(@form)} id="overnight-hint" class="text-sm text-info mb-2">
                {overnight_hint(@form)}
              </p>
              <.input
                field={@form[:position]}
                type="number"
                label="Priorität (kleinere Zahl wird zuerst angerufen)"
                min="0"
              />
              <.input field={@form[:active]} type="checkbox" label="Aktiv" />

              <div class="modal-action">
                <button
                  :if={@live_action == :edit}
                  type="button"
                  id="delete-shift"
                  phx-click="ask_delete_shift"
                  class="btn btn-error mr-auto"
                >
                  Löschen
                </button>
                <.button patch={~p"/schedule"}>Abbrechen</.button>
                <.button variant="primary" phx-disable-with="Speichere...">Speichern</.button>
              </div>
            </.form>
          <% end %>
        </div>
        <.link patch={~p"/schedule"} class="modal-backdrop">Schließen</.link>
      </div>

      <div
        :if={@live_action == :new_override}
        id="override-modal"
        class="modal modal-open modal-bottom sm:modal-middle"
      >
        <div class="modal-box">
          <h3 class="text-lg font-semibold mb-2">Ausnahme anlegen</h3>

          <%= if @people == [] do %>
            <p>
              Zuerst eine Person anlegen:
              <.link navigate={~p"/people/new"} class="link">Person anlegen</.link>
            </p>
            <div class="modal-action">
              <.button patch={~p"/schedule"}>Schließen</.button>
            </div>
          <% else %>
            <.form
              for={@override_form}
              id="override-form"
              phx-change="validate_override"
              phx-submit="save_override"
            >
              <.input
                field={@override_form[:person_id]}
                type="select"
                label="Person"
                options={person_options(@people)}
                prompt="Bitte wählen"
                required
              />
              <.input
                field={@override_form[:kind]}
                type="select"
                label="Art"
                options={for kind <- Override.kinds(), do: {kind_label(kind), kind}}
              />
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-2">
                <.input
                  field={@override_form[:starts_at]}
                  type="datetime-local"
                  label="Von"
                  required
                />
                <.input field={@override_form[:ends_at]} type="datetime-local" label="Bis" required />
              </div>
              <.input field={@override_form[:note]} type="text" label="Notiz (optional)" />

              <div class="modal-action">
                <.button patch={~p"/schedule"}>Abbrechen</.button>
                <.button variant="primary" phx-disable-with="Speichere...">Speichern</.button>
              </div>
            </.form>
          <% end %>
        </div>
        <.link patch={~p"/schedule"} class="modal-backdrop">Schließen</.link>
      </div>

      <%!-- Sits after the shift dialog in the DOM, so it lies on top of it. --%>
      <.confirm_modal
        :if={@confirm_delete_shift}
        id="confirm-delete-shift"
        title="Schicht löschen?"
        confirm="Löschen"
        on_confirm={JS.push("delete")}
        on_cancel={JS.push("cancel_delete_shift")}
      >
        Die Schicht verschwindet aus dem Wochenplan.
      </.confirm_modal>

      <.confirm_modal
        :if={@confirm_delete_override}
        id="confirm-delete-override"
        title="Ausnahme löschen?"
        confirm="Löschen"
        on_confirm={JS.push("delete_override", value: %{id: @confirm_delete_override.id})}
        on_cancel={JS.push("cancel_delete_override")}
      >
        Danach gilt für {@confirm_delete_override.person.name} wieder der Wochenplan.
      </.confirm_modal>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Schedule.subscribe()
      Directory.subscribe()
      schedule_tick()
    end

    {:ok,
     socket
     |> assign(:page_title, "Wochenplan")
     |> assign(:hour_lines, @hour_lines)
     |> assign(:confirm_delete_shift, false)
     |> assign(:confirm_delete_override, nil)
     |> assign_now()
     |> load()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params), do: assign(socket, :shift, nil)

  defp apply_action(socket, :new_override, _params), do: reset_override_form(socket)

  defp apply_action(socket, :new, params) do
    shift = %Shift{
      day_of_week: parse_day(params["day"]),
      starts_at: parse_time(params["from"], ~T[08:00:00]),
      ends_at: parse_time(params["to"], ~T[16:00:00])
    }

    socket
    |> assign(:shift, shift)
    |> assign(:form, to_form(Schedule.change_shift(shift)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    shift = Schedule.get_shift!(id)

    socket
    |> assign(:shift, shift)
    |> assign(:form, to_form(Schedule.change_shift(shift)))
  end

  @impl true
  def handle_event("select_range", %{"day" => day, "from" => from, "to" => to}, socket) do
    params = %{
      day: day,
      from: ScheduleGrid.format_minutes(from),
      # a selection down to midnight ends at 00:00 (of the next day)
      to: ScheduleGrid.format_minutes(rem(to, 1440))
    }

    {:noreply, push_patch(socket, to: ~p"/schedule/shifts/new?#{params}")}
  end

  def handle_event("validate", %{"shift" => params}, socket) do
    changeset = Schedule.change_shift(socket.assigns.shift, params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"shift" => params}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> Schedule.create_shift(params)
        :edit -> Schedule.update_shift(socket.assigns.shift, params)
      end

    case result do
      {:ok, _shift} ->
        {:noreply,
         socket
         |> put_flash(:info, "Schicht gespeichert.")
         |> load()
         |> push_patch(to: ~p"/schedule")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("ask_delete_shift", _params, socket) do
    {:noreply, assign(socket, :confirm_delete_shift, true)}
  end

  def handle_event("cancel_delete_shift", _params, socket) do
    {:noreply, assign(socket, :confirm_delete_shift, false)}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Schedule.delete_shift(socket.assigns.shift)

    {:noreply,
     socket
     |> assign(:confirm_delete_shift, false)
     |> put_flash(:info, "Schicht gelöscht.")
     |> load()
     |> push_patch(to: ~p"/schedule")}
  end

  def handle_event("ask_delete_override", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete_override, Schedule.get_override!(id))}
  end

  def handle_event("cancel_delete_override", _params, socket) do
    {:noreply, assign(socket, :confirm_delete_override, nil)}
  end

  def handle_event("validate_override", %{"override" => params}, socket) do
    changeset = Schedule.change_override(%Override{}, params)
    {:noreply, assign(socket, override_form: to_form(changeset, action: :validate))}
  end

  def handle_event("save_override", %{"override" => params}, socket) do
    case Schedule.create_override(params) do
      {:ok, _override} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ausnahme gespeichert.")
         |> load()
         |> push_patch(to: ~p"/schedule")}

      {:error, changeset} ->
        {:noreply, assign(socket, override_form: to_form(changeset))}
    end
  end

  def handle_event("delete_override", %{"id" => id}, socket) do
    {:ok, _} = id |> Schedule.get_override!() |> Schedule.delete_override()

    {:noreply,
     socket
     |> assign(:confirm_delete_override, nil)
     |> put_flash(:info, "Ausnahme gelöscht.")
     |> load()}
  end

  @impl true
  def handle_info({:schedule_changed, _}, socket), do: {:noreply, load(socket)}
  def handle_info({:person_changed, _}, socket), do: {:noreply, load(socket)}

  def handle_info(:tick, socket) do
    schedule_tick()
    {:noreply, assign_now(socket)}
  end

  defp load(socket) do
    shifts = Schedule.list_shifts()

    socket
    |> assign(:grid, ScheduleGrid.layout(shifts))
    |> assign(:people, Directory.list_people())
    |> assign(:overrides, Schedule.list_upcoming_overrides())
  end

  # Default: absent from today 00:00 for one day.
  defp reset_override_form(socket) do
    today = DateTime.utc_now() |> Schedule.local_naive() |> NaiveDateTime.to_date()
    start = NaiveDateTime.new!(today, ~T[00:00:00])

    override = %Override{
      kind: :block,
      starts_at: start,
      ends_at: NaiveDateTime.add(start, 1, :day)
    }

    assign(socket, :override_form, to_form(Schedule.change_override(override)))
  end

  defp kind_label(kind), do: Map.fetch!(@kind_labels, kind)

  defp format_naive(%NaiveDateTime{} = n) do
    Calendar.strftime(n, "%a %d.%m.%Y %H:%M",
      abbreviated_day_of_week_names: &ScheduleGrid.day_abbr/1
    )
  end

  defp assign_now(socket) do
    local = Schedule.local_naive(DateTime.utc_now())

    socket
    |> assign(:now, local)
    |> assign(:now_day, Date.day_of_week(local))
    |> assign(:now_minute, local.hour * 60 + local.minute)
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, :timer.seconds(60))

  defp person_options(people) do
    for p <- people, do: {if(p.active, do: p.name, else: "#{p.name} (inaktiv)"), p.id}
  end

  defp shift_title(shift) do
    "#{shift.person.name}: #{ScheduleGrid.day_name(shift.day_of_week)} " <>
      "#{ScheduleGrid.format_time(shift.starts_at)}–#{ScheduleGrid.format_time(shift.ends_at)}" <>
      ", Reihenfolge #{shift.position}"
  end

  # Explains overnight / 24h shifts while the form is being filled in.
  defp overnight_hint(form) do
    with %Time{} = from <- form_time(form[:starts_at].value),
         %Time{} = to <- form_time(form[:ends_at].value),
         day when day in 1..7 <- form_day(form[:day_of_week].value) do
      next = ScheduleGrid.day_name(ScheduleGrid.next_day(day))

      case Time.compare(to, from) do
        :gt -> nil
        :eq -> "24 Stunden – bis #{next}, #{ScheduleGrid.format_time(to)} Uhr."
        :lt when to == ~T[00:00:00] -> "Endet um Mitternacht."
        :lt -> "Läuft über Mitternacht bis #{next}, #{ScheduleGrid.format_time(to)} Uhr."
      end
    else
      _ -> nil
    end
  end

  defp form_time(%Time{} = t), do: t

  defp form_time(value) when is_binary(value) do
    case Time.from_iso8601(if String.length(value) == 5, do: value <> ":00", else: value) do
      {:ok, t} -> t
      _ -> nil
    end
  end

  defp form_time(_), do: nil

  defp form_day(day) when is_integer(day), do: day

  defp form_day(day) when is_binary(day) do
    case Integer.parse(day) do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp form_day(_), do: nil

  defp parse_day(value) do
    case form_day(value) do
      day when day in 1..7 -> day
      _ -> 1
    end
  end

  defp parse_time(value, default), do: form_time(value) || default
end
