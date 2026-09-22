defmodule HermesWeb.OverrideLive do
  @moduledoc """
  One-off exceptions to the weekly plan: holidays, sick leave, swaps and
  extra duty. Only current and future exceptions are listed.
  """
  use HermesWeb, :live_view

  alias Hermes.Directory
  alias Hermes.Schedule
  alias Hermes.Schedule.Override

  @kind_labels %{
    add: "Im Dienst (Vertretung / zusätzlich)",
    block: "Abwesend (Urlaub, krank …)"
  }

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
        Ausnahmen
        <:subtitle>
          Gehen dem <.link navigate={~p"/schedule"} class="link">Wochenplan</.link> vor. Für einen
          Tausch: die eine Person als abwesend, die andere als im Dienst eintragen.
        </:subtitle>
      </.header>

      <%= if @people == [] do %>
        <p>
          Zuerst eine Person anlegen:
          <.link navigate={~p"/people/new"} class="link">Person anlegen</.link>
        </p>
      <% else %>
        <.form for={@form} id="override-form" phx-change="validate" phx-submit="save">
          <div class="grid sm:grid-cols-2 gap-x-4">
            <.input
              field={@form[:person_id]}
              type="select"
              label="Person"
              options={for p <- @people, do: {p.name, p.id}}
              prompt="Bitte wählen"
              required
            />
            <.input
              field={@form[:kind]}
              type="select"
              label="Art"
              options={for kind <- Override.kinds(), do: {kind_label(kind), kind}}
            />
            <.input field={@form[:starts_at]} type="datetime-local" label="Von" required />
            <.input field={@form[:ends_at]} type="datetime-local" label="Bis" required />
          </div>
          <.input field={@form[:note]} type="text" label="Notiz (optional)" />
          <.button variant="primary" phx-disable-with="Speichere...">Ausnahme speichern</.button>
        </.form>
      <% end %>

      <div class="divider" />

      <p :if={@empty?} id="overrides-empty" class="text-base-content/70">
        Keine aktuellen oder geplanten Ausnahmen.
      </p>

      <.table :if={!@empty?} id="overrides" rows={@streams.overrides}>
        <:col :let={{_id, o}} label="Person">{o.person.name}</:col>
        <:col :let={{_id, o}} label="Art">
          <span class={["badge badge-sm", (o.kind == :block && "badge-warning") || "badge-success"]}>
            {if o.kind == :block, do: "abwesend", else: "im Dienst"}
          </span>
        </:col>
        <:col :let={{_id, o}} label="Zeitraum">
          {format_naive(o.starts_at)} – {format_naive(o.ends_at)}
        </:col>
        <:col :let={{_id, o}} label="Notiz">{o.note}</:col>
        <:action :let={{id, o}}>
          <.link
            phx-click={JS.push("delete", value: %{id: o.id}) |> hide("##{id}")}
            data-confirm="Ausnahme wirklich löschen?"
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
    if connected?(socket), do: Schedule.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Ausnahmen")
     |> assign(:people, Directory.list_people())
     |> reset_form()
     |> load()}
  end

  @impl true
  def handle_event("validate", %{"override" => params}, socket) do
    changeset = Schedule.change_override(%Override{}, params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"override" => params}, socket) do
    case Schedule.create_override(params) do
      {:ok, _override} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ausnahme gespeichert.")
         |> reset_form()
         |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = id |> Schedule.get_override!() |> Schedule.delete_override()
    {:noreply, socket |> put_flash(:info, "Ausnahme gelöscht.") |> load()}
  end

  @impl true
  def handle_info({:schedule_changed, _}, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    overrides = Schedule.list_upcoming_overrides()

    socket
    |> assign(:empty?, overrides == [])
    |> stream(:overrides, overrides, reset: true)
  end

  # Default: absent from today 00:00 for one day.
  defp reset_form(socket) do
    today = DateTime.utc_now() |> Schedule.local_naive() |> NaiveDateTime.to_date()
    start = NaiveDateTime.new!(today, ~T[00:00:00])

    override = %Override{
      kind: :block,
      starts_at: start,
      ends_at: NaiveDateTime.add(start, 1, :day)
    }

    assign(socket, :form, to_form(Schedule.change_override(override)))
  end

  defp kind_label(kind), do: Map.fetch!(@kind_labels, kind)

  @doc false
  def format_naive(%NaiveDateTime{} = n) do
    Calendar.strftime(n, "%a %d.%m.%Y %H:%M",
      abbreviated_day_of_week_names: fn day -> HermesWeb.ScheduleGrid.day_abbr(day) end
    )
  end
end
