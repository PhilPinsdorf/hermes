defmodule Hermes.Sounds do
  @moduledoc """
  The announcements Asterisk plays.

  The files live in a volume both containers share: Hermes writes them,
  Asterisk reads them. Format: WAV, 8 kHz, 16 bit, mono — what the phone
  network uses anyway.

  Where an announcement comes from, in this order:

    1. a file uploaded in the web UI (kept until it is replaced)
    2. audio generated with `Hermes.Speech` from the text in the settings
    3. the default announcement shipped with the release

  Next to every file a `.txt` marker records what it was made from, so audio
  is only regenerated when the text really changed — never during a call.
  """

  require Logger

  alias Hermes.Schedule
  alias Hermes.Settings
  alias Hermes.Speech
  alias HermesWeb.ScheduleGrid

  @sounds %{
    # played to the caller when nobody is on duty (or a call was rejected with 3)
    no_one_on_duty: "no-one-on-duty",
    # played to the caller when everybody on duty is already in a call
    all_busy: "all-busy",
    # played to the called person only, before the call is put through
    confirm: "confirm"
  }

  @default_texts %{
    no_one_on_duty:
      "Zurzeit ist leider niemand erreichbar. Bitte rufen Sie später noch einmal an.",
    all_busy:
      "Alle Ansprechpartner sind gerade im Gespräch. Bitte rufen Sie in Kürze noch einmal an.",
    confirm:
      "Anruf für die Bereitschaft. Zum Annehmen die 1, zum Weitergeben die 2, zum Abweisen die 3."
  }

  @upload_marker "<eigene Aufnahme>"
  # Shipped with the release: replaced as soon as speech synthesis is available,
  # so an installation does not keep the robotic fallback voice forever.
  @default_marker "<mitgeliefert>"

  ## paths

  @doc "Directory the sound files live in (identical in both containers)."
  def dir, do: Application.get_env(:hermes, :sounds_dir, "/var/lib/asterisk/sounds/hermes")

  @doc "Known announcements."
  def names, do: Map.keys(@sounds)

  @doc """
  ARI media URI for an announcement, e.g.
  `"sound:/var/lib/asterisk/sounds/hermes/no-one-on-duty"` (Asterisk appends
  the file extension itself).
  """
  def media(name), do: "sound:" <> path(name)

  @doc "Path without extension, as Asterisk expects it."
  def path(name), do: Path.join(dir(), Map.fetch!(@sounds, name))

  @doc "Path of the actual file on disk."
  def file(name), do: path(name) <> ".wav"

  defp marker_file(name), do: path(name) <> ".txt"

  # What the audio was made from: the voice plus the text. A different voice
  # (or text) therefore regenerates the announcement.
  defp marker_for(text), do: Speech.voice_name() <> "|" <> text

  ## texts

  @doc "The text an announcement is spoken from, with the default as fallback."
  def text(name, settings \\ nil) do
    settings = settings || Settings.get()

    case Map.get(settings, text_field(name)) do
      text when is_binary(text) ->
        case String.trim(text) do
          "" -> default_text(name)
          trimmed -> trimmed
        end

      _ ->
        default_text(name)
    end
  end

  @doc "The text used when nothing was configured."
  def default_text(name), do: Map.fetch!(@default_texts, name)

  @doc "Settings field holding the text of an announcement."
  def text_field(:no_one_on_duty), do: :text_no_one_on_duty
  def text_field(:all_busy), do: :text_all_busy
  def text_field(:confirm), do: :text_confirm

  @doc """
  What the file on disk was made from: the text, the upload marker, or `nil`
  when nothing is there yet.
  """
  def source_of(name) do
    case File.read(marker_file(name)) do
      {:ok, content} -> String.trim(content)
      {:error, _} -> nil
    end
  end

  @doc "Whether this announcement is an uploaded file."
  def uploaded?(name), do: source_of(name) == @upload_marker

  @doc "Marker written for uploaded files."
  def upload_marker, do: @upload_marker

  @doc "Marker written for the announcements shipped with the release."
  def default_marker, do: @default_marker

  @doc "Whether this announcement is still the shipped fallback."
  def shipped?(name), do: source_of(name) == @default_marker

  ## generating

  @doc """
  Makes sure every announcement matches its text. Uploaded files are left
  alone. Returns the names that were regenerated.
  """
  def refresh(settings \\ nil) do
    settings = settings || Settings.get()

    case File.mkdir_p(dir()) do
      :ok ->
        Enum.filter(names(), &refresh_one(&1, settings))

      {:error, reason} ->
        Logger.warning("sounds directory unavailable: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Same as `refresh/1`, but in the background (used after saving settings).
  Switched off in tests, where no audio is generated anyway.
  """
  def refresh_async(settings \\ nil) do
    if Application.get_env(:hermes, :generate_sounds, true) do
      Task.Supervisor.start_child(Hermes.TaskSupervisor, fn -> refresh(settings) end)
    else
      :ok
    end
  end

  defp refresh_one(name, settings) do
    wanted = text(name, settings)

    cond do
      uploaded?(name) -> false
      source_of(name) == marker_for(wanted) and File.exists?(file(name)) -> false
      true -> write(name, wanted)
    end
  end

  defp write(name, wanted) do
    case Speech.synthesize(wanted, file(name)) do
      :ok ->
        File.write(marker_file(name), marker_for(wanted))
        Logger.info("announcement #{name} regenerated")
        true

      {:error, reason} ->
        keep_or_install_default(name, reason)
        false
    end
  end

  # Without Piper (or when it fails) whatever is there stays, and if nothing
  # is there the shipped announcement is used: a call always has something to play.
  defp keep_or_install_default(name, reason) do
    if File.exists?(file(name)) do
      # No speech synthesis installed is a normal setup, not a problem.
      level = if reason == :unavailable, do: :debug, else: :warning

      Logger.log(
        level,
        "announcement #{name} not regenerated (#{inspect(reason)}), keeping the old one"
      )
    else
      install(name)
      Logger.info("announcement #{name}: using the shipped default (#{inspect(reason)})")
    end
  end

  @doc """
  Takes an uploaded audio file as the announcement. It is converted to the
  telephone format; from then on the text no longer overwrites it.
  """
  def install_upload(name, source_path) do
    with :ok <- File.mkdir_p(dir()),
         :ok <- Speech.convert(source_path, file(name)) do
      File.write(marker_file(name), @upload_marker)
      :ok
    end
  end

  @doc "Drops an uploaded file, so the text is spoken again."
  def reset(name) do
    File.rm(marker_file(name))
    File.rm(file(name))
    refresh()
    :ok
  end

  @doc """
  Copies missing default announcements into the sounds directory, so there is
  always something to play (called at start).
  """
  def install_defaults do
    case File.mkdir_p(dir()) do
      :ok ->
        copied =
          names()
          |> Enum.reject(&File.exists?(file(&1)))
          |> Enum.filter(&install/1)

        {:ok, copied}

      error ->
        error
    end
  end

  defp install(name) do
    case File.cp(default_file(name), file(name)) do
      :ok ->
        File.write(marker_file(name), @default_marker)
        true

      {:error, reason} ->
        Logger.warning("could not install sound #{name}: #{inspect(reason)}")
        false
    end
  end

  defp default_file(name) do
    Application.app_dir(:hermes, ["priv", "sounds", Map.fetch!(@sounds, name) <> ".wav"])
  end

  ## "nobody on duty" including the next shift

  @doc """
  Media for the "nobody on duty" announcement. When the next shift is known
  and the setting is on, a variant naming it is used —
  "… ab Montag um 8 Uhr sind wir wieder erreichbar."

  The variant is cached per text. If it is not ready yet, the normal
  announcement plays and the variant is generated in the background, so a
  call never waits for the synthesizer.
  """
  def no_one_on_duty_media(next_change \\ nil, settings \\ nil) do
    settings = settings || Settings.get()

    with true <- settings.announce_next_shift,
         {%DateTime{} = at, [_ | _]} <- next_change,
         text when is_binary(text) <- next_shift_text(at, settings) do
      path = variant_path(text)

      if File.exists?(path <> ".wav") do
        "sound:" <> path
      else
        generate_variant_async(text, path)
        media(:no_one_on_duty)
      end
    else
      _ -> media(:no_one_on_duty)
    end
  end

  @doc """
  The announcement text including the next shift, or `nil` when that cannot
  be said sensibly (more than a week away).
  """
  def next_shift_text(%DateTime{} = at, settings \\ nil) do
    settings = settings || Settings.get()
    local = Schedule.local_naive(at)
    today = DateTime.utc_now() |> Schedule.local_naive() |> NaiveDateTime.to_date()

    day =
      case Date.diff(NaiveDateTime.to_date(local), today) do
        0 -> "heute"
        1 -> "morgen"
        diff when diff in 2..6 -> "am " <> ScheduleGrid.day_name(Date.day_of_week(local))
        _ -> nil
      end

    if day do
      text(:no_one_on_duty, settings) <>
        " Ab #{day} um #{spoken_time(local)} sind wir wieder erreichbar."
    end
  end

  defp spoken_time(%NaiveDateTime{hour: hour, minute: 0}), do: "#{hour} Uhr"

  defp spoken_time(%NaiveDateTime{hour: hour, minute: minute}),
    do: "#{hour} Uhr #{String.pad_leading(Integer.to_string(minute), 2, "0")}"

  defp variant_path(text) do
    hash = :crypto.hash(:sha256, text) |> Base.encode16(case: :lower) |> binary_part(0, 16)
    Path.join([dir(), "variants", "no-one-on-duty-" <> hash])
  end

  defp generate_variant_async(text, path) do
    if Application.get_env(:hermes, :generate_sounds, true) do
      do_generate_variant_async(text, path)
    end
  end

  defp do_generate_variant_async(text, path) do
    Task.Supervisor.start_child(Hermes.TaskSupervisor, fn ->
      case Speech.synthesize(text, path <> ".wav") do
        :ok -> Logger.info("announcement variant generated")
        {:error, reason} -> Logger.debug("announcement variant not generated: #{inspect(reason)}")
      end
    end)
  end

  @doc """
  Removes cached variants that have not been touched for `days` days.
  """
  def prune_variants(days \\ 30) do
    cutoff = System.os_time(:second) - days * 86_400
    variants = Path.join(dir(), "variants")

    case File.ls(variants) do
      {:ok, files} ->
        files
        |> Enum.map(&Path.join(variants, &1))
        |> Enum.filter(&older_than?(&1, cutoff))
        |> Enum.count(&(File.rm(&1) == :ok))

      {:error, _} ->
        0
    end
  end

  defp older_than?(file, cutoff) do
    case File.stat(file, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> mtime < cutoff
      _ -> false
    end
  end
end
