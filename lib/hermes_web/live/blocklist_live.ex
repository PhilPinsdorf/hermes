defmodule HermesWeb.BlocklistLive do
  @moduledoc """
  Numbers that never reach a phone. Blocking happens either here or straight
  from a row in the call log.
  """
  use HermesWeb, :live_view

  alias Hermes.Blocklist
  alias Hermes.Blocklist.BlockedNumber
  alias Hermes.Directory.PhoneNumber

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
        Blockierte Nummern
        <:subtitle>
          Anrufe von diesen Nummern hören eine Ansage; es klingelt kein Telefon. Den Text
          dazu gibt es unter <.link navigate={~p"/settings"} class="link">Einstellungen</.link>.
        </:subtitle>
        <:actions>
          <.button variant="primary" patch={~p"/blocked/new"}>
            <.icon name="hero-plus" /> Nummer blockieren
          </.button>
        </:actions>
      </.header>

      <p :if={@blocked == []} id="blocked-empty" class="text-base-content/70">
        Keine Nummer blockiert.
      </p>

      <%!-- Phones: one card per number, the number itself first. --%>
      <ul :if={@blocked != []} id="blocked-cards" class="sm:hidden space-y-2">
        <li
          :for={entry <- @blocked}
          id={"blocked-card-#{entry.id}"}
          class="card card-body gap-1 p-4"
        >
          <p class="text-lg font-semibold leading-tight tabular-nums">
            {PhoneNumber.format(entry.number)}
          </p>
          <p :if={entry.note not in [nil, ""]} class="text-base">{entry.note}</p>
          <p class="text-sm text-base-content/60">blockiert seit {format_date(entry.inserted_at)}</p>

          <div class="pt-2">
            <button
              type="button"
              id={"unblock-card-#{entry.id}"}
              phx-click={JS.push("ask_unblock", value: %{id: entry.id})}
              class="btn btn-sm btn-primary w-full"
            >
              Freigeben
            </button>
          </div>
        </li>
      </ul>

      <div :if={@blocked != []} class="hidden sm:block">
        <.table
          :if={@blocked != []}
          id="blocked"
          rows={@blocked}
          row_id={&"blocked-#{&1.id}"}
        >
          <:col :let={entry} label="Nummer">{PhoneNumber.format(entry.number)}</:col>
          <:col :let={entry} label="Notiz">
            <span :if={entry.note in [nil, ""]} class="text-base-content/50">–</span>
            {entry.note}
          </:col>
          <:col :let={entry} label="Blockiert seit">{format_date(entry.inserted_at)}</:col>
          <:action :let={entry}>
            <button
              type="button"
              id={"unblock-#{entry.id}"}
              phx-click={JS.push("ask_unblock", value: %{id: entry.id})}
              class="btn btn-xs btn-primary"
            >
              Freigeben
            </button>
          </:action>
        </.table>
      </div>

      <.confirm_modal
        :if={@pending_unblock}
        id="confirm-unblock"
        title="Nummer freigeben?"
        confirm="Freigeben"
        variant="primary"
        on_confirm={JS.push("unblock", value: %{id: @pending_unblock.id})}
        on_cancel={JS.push("cancel_unblock")}
      >
        {PhoneNumber.format(@pending_unblock.number)} erreicht danach wieder die Bereitschaft.
      </.confirm_modal>

      <div
        :if={@live_action == :new}
        id="block-modal"
        class="modal modal-open modal-bottom sm:modal-middle"
      >
        <div class="modal-box">
          <h3 class="text-lg font-semibold mb-2">Nummer blockieren</h3>

          <.form for={@form} id="block-form" phx-change="validate" phx-submit="save">
            <.input
              field={@form[:number]}
              type="tel"
              label="Rufnummer"
              placeholder="030 1234567"
              required
              phx-mounted={JS.focus()}
            />
            <.input field={@form[:note]} type="text" label="Notiz (optional)" />

            <div class="modal-action">
              <.button patch={~p"/blocked"}>Abbrechen</.button>
              <.button variant="primary" phx-disable-with="Speichere...">Blockieren</.button>
            </div>
          </.form>
        </div>
        <.link patch={~p"/blocked"} class="modal-backdrop">Schließen</.link>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Blocklist.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Blockierte Nummern")
     |> assign(:pending_unblock, nil)
     |> load()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params), do: socket

  defp apply_action(socket, :new, _params),
    do: assign(socket, :form, to_form(Blocklist.change(%BlockedNumber{})))

  @impl true
  def handle_event("validate", %{"blocked_number" => params}, socket) do
    changeset = Blocklist.change(%BlockedNumber{}, params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"blocked_number" => params}, socket) do
    case Blocklist.block(params) do
      {:ok, _blocked} ->
        {:noreply,
         socket
         |> put_flash(:info, "Nummer blockiert.")
         |> load()
         |> push_patch(to: ~p"/blocked")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("ask_unblock", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_unblock, Blocklist.get!(id))}
  end

  def handle_event("cancel_unblock", _params, socket) do
    {:noreply, assign(socket, :pending_unblock, nil)}
  end

  def handle_event("unblock", %{"id" => id}, socket) do
    {:ok, _} = id |> Blocklist.get!() |> Blocklist.unblock()

    {:noreply,
     socket
     |> assign(:pending_unblock, nil)
     |> put_flash(:info, "Nummer freigegeben.")
     |> load()}
  end

  @impl true
  def handle_info({:blocklist_changed, _entry}, socket), do: {:noreply, load(socket)}

  defp load(socket), do: assign(socket, :blocked, Blocklist.list())

  defp format_date(%DateTime{} = at) do
    at
    |> Hermes.Schedule.local_naive()
    |> Calendar.strftime("%d.%m.%Y")
  end
end
