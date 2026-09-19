defmodule HermesWeb.SettingsLive do
  use HermesWeb, :live_view

  alias Hermes.Directory.PhoneNumber
  alias Hermes.Settings

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Einstellungen
        <:subtitle>Gelten für alle Anrufe dieser Installation.</:subtitle>
      </.header>

      <.form for={@form} id="settings-form" phx-change="validate" phx-submit="save">
        <h2 class="text-lg font-semibold mt-4">Anzeige auf dem Handy</h2>
        <.input
          field={@form[:clip_number]}
          type="tel"
          label="Angezeigte Rufnummer (Festnetznummer)"
          placeholder="030 1234567"
        />
        <.input
          field={@form[:clip_display_name]}
          type="text"
          label="Anzeigename"
          placeholder="Bereitschaft"
          required
        />

        <h2 class="text-lg font-semibold mt-8">Klingeln</h2>
        <.input
          field={@form[:ring_timeout_seconds]}
          type="number"
          label="Klingeldauer je Person in Sekunden"
          min="5"
          max="120"
          required
        />
        <.input
          field={@form[:ring_strategy]}
          type="select"
          label="Reihenfolge"
          options={[
            {"Nacheinander (mit Eskalation zur nächsten Person)", :sequential},
            {"Gleichzeitig (wer zuerst annimmt)", :simultaneous}
          ]}
        />
        <p
          :if={simultaneous_degraded?(@form)}
          id="simultaneous-hint"
          class="text-sm text-warning -mt-1 mb-2"
        >
          Mit {@form[:max_external_channels].value} Leitungen bleibt für den Ruf nach draußen nur ein
          Kanal frei – „Gleichzeitig“ klingelt dann automatisch nacheinander.
        </p>
        <.input
          field={@form[:busy_policy]}
          type="select"
          label="Wenn alle Diensthabenden im Gespräch sind"
          options={[{"Ansage abspielen und auflegen", :announce}]}
        />

        <h2 class="text-lg font-semibold mt-8">Anschluss</h2>
        <.input
          field={@form[:max_external_channels]}
          type="number"
          label="Gleichzeitige externe Gespräche"
          min="2"
          max="30"
          required
        />
        <p class="text-sm text-base-content/70 -mt-1 mb-2">
          Ein normaler Fritz!Box-Anschluss erlaubt meist 2. Ein vermitteltes Gespräch belegt beide:
          eines vom Anrufer, eines zum Handy. Ein zweiter Anrufer hört in dieser Zeit das
          Besetztzeichen des Providers – Hermes bekommt diesen Anruf gar nicht zu sehen. Mit einem
          SIP-Trunk (meist 4–8 Kanäle) entfällt diese Grenze.
        </p>

        <footer class="mt-4">
          <.button phx-disable-with="Speichere..." variant="primary">Speichern</.button>
        </footer>
      </.form>

      <div class="divider" />

      <section id="vcard">
        <h2 class="text-lg font-semibold">Kontakt für alle Handys</h2>
        <%= if @setting.clip_number do %>
          <p class="text-base-content/80 my-2">
            Alle weitergeleiteten Anrufe kommen von <strong>{PhoneNumber.format(@setting.clip_number)}</strong>. Damit auf dem Display
            „<strong>{@setting.clip_display_name}</strong>“ steht, lädt jede Person diese eine Datei
            herunter und speichert sie einmal im Adressbuch. Die Datei ist für alle gleich.
          </p>
          <.button href={~p"/settings/contact.vcf"} download>
            <.icon name="hero-arrow-down-tray" /> Kontakt herunterladen (.vcf)
          </.button>
        <% else %>
          <p class="text-base-content/70 my-2">
            Sobald die angezeigte Rufnummer gespeichert ist, gibt es hier den Kontakt zum Download.
          </p>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    setting = Settings.get()

    {:ok,
     socket
     |> assign(:page_title, "Einstellungen")
     |> assign(:setting, setting)
     |> assign(:form, to_form(Settings.change(setting)))}
  end

  @impl true
  def handle_event("validate", %{"setting" => params}, socket) do
    changeset = Settings.change(socket.assigns.setting, params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"setting" => params}, socket) do
    case Settings.update(params) do
      {:ok, setting} ->
        {:noreply,
         socket
         |> assign(:setting, setting)
         |> assign(:form, to_form(Settings.change(setting)))
         |> put_flash(:info, "Einstellungen gespeichert.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # Mirrors the channel guard of the call engine: incoming leg + more than one
  # outgoing leg only fit when the line allows at least 3 concurrent calls.
  defp simultaneous_degraded?(form) do
    to_string(form[:ring_strategy].value) == "simultaneous" and
      case to_integer(form[:max_external_channels].value) do
        nil -> false
        channels -> channels < 3
      end
  end

  defp to_integer(n) when is_integer(n), do: n

  defp to_integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp to_integer(_), do: nil
end
