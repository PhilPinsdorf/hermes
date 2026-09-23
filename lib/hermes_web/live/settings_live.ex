defmodule HermesWeb.SettingsLive do
  use HermesWeb, :live_view

  alias Hermes.Branding
  alias Hermes.Directory.PhoneNumber
  alias Hermes.Settings
  alias Hermes.Sounds
  alias Hermes.Speech

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
        Einstellungen
        <:subtitle>Gelten für alle Anrufe dieser Installation.</:subtitle>
      </.header>

      <section id="branding">
        <h2 class="text-lg font-semibold">Erscheinungsbild</h2>
        <p class="text-sm text-base-content/70 mt-1 mb-3">
          Name und Logo dieser Installation – sie erscheinen in der Kopfzeile, im
          Browser-Tab und auf der Anmeldeseite.
        </p>

        <.form for={@form} id="branding-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:brand_name]} type="text" label="Name der Installation" required />
          <.button variant="primary" phx-disable-with="Speichere...">Speichern</.button>
        </.form>

        <form id="logo-form" phx-submit="upload_logo" phx-change="validate_upload" class="mt-4">
          <span class="fieldset-label">Logo</span>
          <div class="flex flex-wrap items-center gap-3 mt-1">
            <Layouts.brand_mark branding={@branding} class="size-10" />
            <.live_file_input upload={@uploads.logo} class="file-input file-input-sm" />
            <.button phx-disable-with="Lade hoch...">Logo hochladen</.button>
            <button
              :if={@branding.logo?}
              type="button"
              phx-click="remove_logo"
              class="btn btn-sm btn-ghost"
            >
              Logo entfernen
            </button>
          </div>
          <p class="text-sm text-base-content/70 mt-1">
            PNG, JPEG, SVG oder WebP, höchstens 1 MB. Quadratisch sieht am besten aus.
          </p>
          <p :for={entry <- @uploads.logo.entries} class="text-sm text-error">
            {Enum.map_join(upload_errors(@uploads.logo, entry), ", ", &upload_error/1)}
          </p>
        </form>
      </section>

      <div class="divider" />

      <.form for={@form} id="settings-form" phx-change="validate" phx-submit="save">
        <h2 class="text-lg font-semibold">Anzeige auf dem Handy</h2>
        <.input
          field={@form[:clip_number]}
          type="tel"
          label="Angezeigte Rufnummer (Festnetznummer)"
          placeholder="030 1234567"
        />
        <p class="text-sm text-base-content/70 -mt-1 mb-2">
          Welche Nummer tatsächlich beim Angerufenen erscheint, bestimmt die Fritz!Box
          (beim IP-Telefon unter „Ausgehende Anrufe“). Hier dieselbe Nummer eintragen –
          sie landet in der Kontakt-Datei, die alle einmal speichern.
        </p>
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

      <section id="announcements">
        <h2 class="text-lg font-semibold">Ansagen</h2>
        <p class="text-sm text-base-content/70 mt-1 mb-3">
          <%= if @speech_available? do %>
            Die Texte werden nach dem Speichern automatisch vorgelesen und als Ansage
            hinterlegt. Alternativ lässt sich je Ansage eine eigene Aufnahme hochladen.
          <% else %>
            Auf diesem System ist keine Sprachausgabe installiert, deshalb bleiben die
            mitgelieferten Ansagen aktiv. Eigene Aufnahmen lassen sich trotzdem hochladen.
          <% end %>
        </p>

        <div :for={name <- Sounds.names()} id={"announcement-#{name}"} class="mb-6">
          <h3 class="font-semibold">{announcement_title(name)}</h3>
          <p class="text-sm text-base-content/70 mb-1">{announcement_hint(name)}</p>

          <.form for={@form} id={"text-form-#{name}"} phx-submit="save_text" phx-change="validate">
            <input type="hidden" name="name" value={name} />
            <.input
              field={@form[Sounds.text_field(name)]}
              type="textarea"
              label="Text"
              placeholder={Sounds.default_text(name)}
              disabled={Sounds.uploaded?(name)}
            />
            <div class="flex flex-wrap items-center gap-2">
              <.button :if={!Sounds.uploaded?(name)} variant="primary" phx-disable-with="Speichere...">
                Text speichern
              </.button>
              <audio
                id={"player-#{name}"}
                controls
                preload="none"
                class="h-8"
                src={~p"/settings/announcements/#{name}?v=#{@audio_version}"}
              >
              </audio>
              <span :if={Sounds.uploaded?(name)} class="badge badge-info">eigene Aufnahme</span>
              <button
                :if={Sounds.uploaded?(name)}
                type="button"
                phx-click="reset_announcement"
                phx-value-name={name}
                class="btn btn-sm btn-ghost"
              >
                Eigene Aufnahme entfernen
              </button>
            </div>
          </.form>

          <form
            id={"upload-form-#{name}"}
            phx-submit="upload_announcement"
            phx-change="validate_upload"
            class="mt-2"
          >
            <input type="hidden" name="name" value={name} />
            <div class="flex flex-wrap items-center gap-2">
              <.live_file_input upload={@uploads[name]} class="file-input file-input-sm" />
              <.button phx-disable-with="Lade hoch...">Eigene Aufnahme hochladen</.button>
            </div>
            <p :for={entry <- @uploads[name].entries} class="text-sm text-error">
              {Enum.map_join(upload_errors(@uploads[name], entry), ", ", &upload_error/1)}
            </p>
          </form>
        </div>

        <.form for={@form} id="next-shift-form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:announce_next_shift]}
            type="checkbox"
            label="In der Ansage sagen, ab wann wieder jemand erreichbar ist"
          />
          <p class="text-sm text-base-content/70 -mt-1">
            Ergänzt die Ansage um einen Satz wie „Ab morgen um 8 Uhr sind wir wieder erreichbar“,
            berechnet aus dem Wochenplan.
          </p>
        </.form>
      </section>

      <div class="divider" />

      <section id="retention">
        <h2 class="text-lg font-semibold">Anrufprotokoll</h2>
        <.form for={@form} id="retention-form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:call_log_retention_days]}
            type="number"
            label="Anrufe aufbewahren (Tage)"
            min="1"
            max="3650"
            required
          />
          <.input
            field={@form[:call_log_anonymize_after_days]}
            type="number"
            label="Anrufernummern schon vorher entfernen (Tage, leer = nie)"
            min="0"
          />
          <p class="text-sm text-base-content/70 -mt-1 mb-2">
            Telefonnummern sind personenbezogene Daten. Ältere Einträge werden täglich
            automatisch gelöscht; die Statistik bleibt dabei erhalten.
          </p>
          <.button variant="primary" phx-disable-with="Speichere...">Speichern</.button>
        </.form>
      </section>

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
            <.icon name="hero-arrow-down-tray-bold" /> Kontakt herunterladen (.vcf)
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
     |> assign(:speech_available?, Speech.available?())
     |> assign_audio_version()
     |> assign(:form, to_form(Settings.change(setting)))
     |> allow_announcement_uploads()}
  end

  @impl true
  def handle_event("validate", %{"setting" => params}, socket) do
    changeset = Settings.change(socket.assigns.setting, params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save_text", %{"name" => name, "setting" => params}, socket) do
    name = String.to_existing_atom(name)
    field = Sounds.text_field(name)
    message = "Ansage #{announcement_title(name)}: Text gespeichert."
    save(socket, Map.take(params, [to_string(field)]), message)
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("upload_announcement", %{"name" => name}, socket) do
    name = String.to_existing_atom(name)

    results =
      consume_uploaded_entries(socket, name, fn %{path: path}, _entry ->
        {:ok, Sounds.install_upload(name, path)}
      end)

    case results do
      [:ok] ->
        {:noreply,
         socket |> assign_audio_version() |> put_flash(:info, "Eigene Aufnahme übernommen.")}

      [{:error, reason}] ->
        {:noreply,
         put_flash(socket, :error, "Aufnahme konnte nicht übernommen werden: #{inspect(reason)}")}

      [] ->
        {:noreply, put_flash(socket, :error, "Bitte zuerst eine Datei auswählen.")}
    end
  end

  def handle_event("upload_logo", _params, socket) do
    results =
      consume_uploaded_entries(socket, :logo, fn %{path: path}, entry ->
        {:ok, Branding.put_logo(path, entry.client_type)}
      end)

    case results do
      [{:ok, _setting}] ->
        {:noreply, socket |> refresh_branding() |> put_flash(:info, "Logo übernommen.")}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, logo_error(reason))}

      [] ->
        {:noreply, put_flash(socket, :error, "Bitte zuerst eine Datei auswählen.")}
    end
  end

  def handle_event("remove_logo", _params, socket) do
    {:ok, _setting} = Branding.remove_logo()
    {:noreply, socket |> refresh_branding() |> put_flash(:info, "Logo entfernt.")}
  end

  def handle_event("reset_announcement", %{"name" => name}, socket) do
    name |> String.to_existing_atom() |> Sounds.reset()

    {:noreply,
     socket
     |> assign_audio_version()
     |> put_flash(:info, "Eigene Aufnahme entfernt, der Text gilt wieder.")}
  end

  def handle_event("save", %{"setting" => params}, socket) do
    save(socket, params, "Einstellungen gespeichert.")
  end

  # One upload per announcement, so each file input has its own id.
  defp allow_announcement_uploads(socket) do
    socket
    |> allow_upload(:logo, accept: ~w(image/*), max_entries: 1, max_file_size: 1_000_000)
    |> then(fn socket ->
      Enum.reduce(Sounds.names(), socket, fn name, socket ->
        allow_upload(socket, name, accept: ~w(audio/*), max_entries: 1, max_file_size: 10_000_000)
      end)
    end)
  end

  # Announcements keep their URL, so the player needs a hint when the audio
  # behind it changed.
  defp assign_audio_version(socket) do
    assign(socket, :audio_version, System.system_time(:second))
  end

  defp save(socket, params, message) do
    case Settings.update(params) do
      {:ok, setting} ->
        {:noreply,
         socket
         |> assign(:setting, setting)
         |> assign(:form, to_form(Settings.change(setting)))
         |> assign_audio_version()
         |> refresh_branding()
         |> put_flash(:info, message)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # The header shows the logo too, so it has to be re-read after a change.
  defp refresh_branding(socket), do: assign(socket, :branding, Branding.summary())

  defp logo_error(:unsupported_format), do: "Dieses Bildformat wird nicht unterstützt."
  defp logo_error(:too_large), do: "Das Logo darf höchstens 1 MB groß sein."
  defp logo_error(reason), do: "Logo konnte nicht gespeichert werden: #{inspect(reason)}"

  defp announcement_title(:no_one_on_duty), do: "Niemand erreichbar"
  defp announcement_title(:all_busy), do: "Alle im Gespräch"
  defp announcement_title(:confirm), do: "Bestätigung auf dem Handy"
  defp announcement_title(:blocked), do: "Blockierte Nummer"

  defp announcement_hint(:no_one_on_duty),
    do: "Hört der Anrufer, wenn niemand Dienst hat oder niemand annimmt."

  defp announcement_hint(:all_busy),
    do: "Hört der Anrufer, wenn alle Diensthabenden gerade im Gespräch sind."

  defp announcement_hint(:confirm),
    do: "Hört nur die angerufene Person. Sie muss die Tasten 1, 2 und 3 erklären."

  defp announcement_hint(:blocked),
    do: "Hört ein Anrufer, dessen Nummer blockiert ist. Es klingelt dann kein Telefon."

  defp upload_error(:too_large), do: "Datei ist zu groß (max. 10 MB)"
  defp upload_error(:not_accepted), do: "Dateiformat wird nicht unterstützt"
  defp upload_error(:too_many_files), do: "Bitte nur eine Datei"
  defp upload_error(error), do: to_string(error)

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
