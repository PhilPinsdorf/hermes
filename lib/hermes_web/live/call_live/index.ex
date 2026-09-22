defmodule HermesWeb.CallLive.Index do
  @moduledoc """
  The call log, plus what is going on right now.
  """
  use HermesWeb, :live_view

  alias Hermes.Calls
  alias Hermes.Calls.{CallAttempt, CallLog, Log}
  alias Hermes.Directory
  alias Hermes.Directory.PhoneNumber
  alias HermesWeb.CallLive.Labels

  @per_page 50

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
        Anrufe
        <:subtitle>
          Was aus jedem Anruf geworden ist. Ältere Einträge werden automatisch gelöscht
          (<.link navigate={~p"/settings"} class="link">Einstellungen</.link>).
        </:subtitle>
      </.header>

      <section :if={@running != []} id="running-calls" class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title">Gerade im Gespräch</h2>
          <ul class="space-y-1">
            <li :for={call <- @running} id={"running-#{call.channel_id}"} class="flex gap-2 text-sm">
              <span class="badge badge-info badge-sm">{Labels.state(call.state)}</span>
              <span class="font-semibold">{PhoneNumber.format(call.caller)}</span>
              <span class="text-base-content/60">seit {relative_time(call.started_at)}</span>
            </li>
          </ul>
        </div>
      </section>

      <.form
        for={@filter_form}
        id="call-filter"
        phx-change="filter"
        class="grid grid-cols-2 sm:grid-cols-4 gap-x-3"
      >
        <.input
          field={@filter_form[:result]}
          type="select"
          label="Ergebnis"
          options={[{"alle", ""} | Enum.map(CallLog.results(), &{Labels.result(&1), &1})]}
        />
        <.input
          field={@filter_form[:person_id]}
          type="select"
          label="Vermittelt an"
          options={[{"alle", ""} | Enum.map(@people, &{&1.name, &1.id})]}
        />
        <.input field={@filter_form[:from]} type="date" label="Von" />
        <.input field={@filter_form[:to]} type="date" label="Bis" />
      </.form>

      <p class="text-sm text-base-content/70">
        {@total} {if @total == 1, do: "Anruf", else: "Anrufe"}
        <span :if={@total > @per_page}>– gezeigt werden die neuesten {@per_page}</span>
      </p>

      <p :if={@calls == []} id="calls-empty" class="text-base-content/70">
        Keine Anrufe für diese Auswahl.
      </p>

      <.table :if={@calls != []} id="calls" rows={@streams.calls}>
        <:col :let={{_id, call}} label="Zeitpunkt">{format_time(call.started_at)}</:col>
        <:col :let={{_id, call}} label="Anrufer">
          <%= if call.caller_number do %>
            {PhoneNumber.format(call.caller_number)}
          <% else %>
            <span class="text-base-content/50" title="Nummer nach Ablauf der Frist entfernt">
              entfernt
            </span>
          <% end %>
        </:col>
        <:col :let={{_id, call}} label="Ergebnis">
          <span class={["badge badge-sm", Labels.result_class(call.result)]}>
            {Labels.result(call.result)}
          </span>
        </:col>
        <:col :let={{_id, call}} label="Vermittelt an">
          {(call.person && call.person.name) || "–"}
        </:col>
        <:col :let={{_id, call}} label="Dauer">{duration(call)}</:col>
        <:col :let={{_id, call}} label="Versuche">
          <span :if={call.attempts == []} class="text-base-content/50">–</span>
          <span :for={attempt <- call.attempts} class="mr-2 inline-block whitespace-nowrap">
            {attempt.person_name}
            <span class={["badge badge-xs", Labels.outcome_class(attempt.outcome)]}>
              {Labels.outcome(attempt.outcome)}
            </span>
          </span>
        </:col>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Calls.subscribe()
      schedule_tick()
    end

    {:ok,
     socket
     |> assign(:page_title, "Anrufe")
     |> assign(:per_page, @per_page)
     |> assign(:people, Directory.list_people())
     |> assign(:filters, %{})
     |> assign(:filter_form, to_form(%{}, as: :filter))
     |> assign(:running, Calls.running())
     |> load_calls()}
  end

  @impl true
  def handle_event("filter", %{"filter" => params}, socket) do
    filters = build_filters(params)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(params, as: :filter))
     |> load_calls()}
  end

  @impl true
  def handle_info({:call_logged, _id}, socket), do: {:noreply, load_calls(socket)}

  def handle_info({event, _channel_id}, socket)
      when event in [:call_started, :call_ended, :call_bridged] do
    {:noreply, assign(socket, :running, Calls.running())}
  end

  # Keeps the "since" of running calls moving.
  def handle_info(:tick, socket) do
    schedule_tick()
    {:noreply, assign(socket, :running, Calls.running())}
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, :timer.seconds(15))

  defp load_calls(socket) do
    filters = Map.put(socket.assigns.filters, :limit, @per_page)
    calls = Log.list_calls(filters)

    socket
    |> assign(:calls, calls)
    |> assign(:total, Log.count_calls(socket.assigns.filters))
    |> stream(:calls, calls, reset: true)
  end

  defp build_filters(params) do
    %{}
    |> put_filter(:result, params["result"])
    |> put_filter(:person_id, params["person_id"])
    |> put_date(:from, params["from"])
    |> put_date(:to, params["to"])
  end

  defp put_filter(filters, _key, value) when value in [nil, ""], do: filters
  defp put_filter(filters, :person_id, value), do: Map.put(filters, :person_id, value)
  defp put_filter(filters, key, value), do: Map.put(filters, key, value)

  defp put_date(filters, key, value) do
    case Date.from_iso8601(value || "") do
      {:ok, date} -> Map.put(filters, key, date)
      _ -> filters
    end
  end

  defp format_time(%DateTime{} = at) do
    at
    |> Hermes.Schedule.local_naive()
    |> Calendar.strftime("%a %d.%m.%Y %H:%M",
      abbreviated_day_of_week_names: &HermesWeb.ScheduleGrid.day_abbr/1
    )
  end

  defp relative_time(%DateTime{} = at) do
    case DateTime.diff(DateTime.utc_now(), at) do
      seconds when seconds < 60 -> "#{seconds} s"
      seconds -> "#{div(seconds, 60)} min"
    end
  end

  defp duration(%CallLog{result: :bridged, talk_seconds: talk}) when is_integer(talk),
    do: format_duration(talk)

  defp duration(%CallLog{total_seconds: total}) when is_integer(total), do: format_duration(total)
  defp duration(_call), do: "–"

  defp format_duration(seconds) when seconds < 60, do: "#{seconds} s"

  defp format_duration(seconds) do
    "#{div(seconds, 60)}:#{String.pad_leading(Integer.to_string(rem(seconds, 60)), 2, "0")} min"
  end

  @doc false
  def outcomes, do: CallAttempt.outcomes()
end
