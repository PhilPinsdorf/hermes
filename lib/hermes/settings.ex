defmodule Hermes.Settings do
  @moduledoc """
  Global, instance-wide settings (one row per deployment).
  """

  alias Hermes.Repo
  alias Hermes.Settings.Setting

  @id 1

  @doc """
  Returns the settings, creating the row with defaults on first access.
  """
  def get do
    case Repo.get(Setting, @id) do
      nil ->
        # on_conflict: two concurrent first accesses must not crash each other.
        Repo.insert!(%Setting{id: @id}, on_conflict: :nothing, conflict_target: :id)
        Repo.get!(Setting, @id)

      setting ->
        setting
    end
  end

  @doc """
  Updates the settings.
  """
  def update(attrs) do
    result =
      get()
      |> Setting.changeset(attrs)
      |> Repo.update()

    with {:ok, setting} <- result do
      # Texts may have changed: rebuild the audio in the background.
      Hermes.Sounds.refresh_async(setting)
    end

    broadcast(result)
  end

  @doc """
  Turns forwarding on or off globally. While it is off, callers hear the
  announcement and no phone rings.
  """
  def set_forwarding(enabled?) when is_boolean(enabled?) do
    paused_at = if enabled?, do: nil, else: DateTime.utc_now() |> DateTime.truncate(:second)

    get()
    |> Ecto.Changeset.change(%{forwarding_enabled: enabled?, forwarding_paused_at: paused_at})
    |> Repo.update()
    |> broadcast()
  end

  @doc "Whether calls are forwarded at all right now."
  def forwarding_enabled?, do: get().forwarding_enabled

  @doc """
  Subscribes to `{:settings_changed, %Setting{}}` (used by the overview, so a
  switch flipped on one device shows up on the others).
  """
  def subscribe, do: Phoenix.PubSub.subscribe(Hermes.PubSub, "settings")

  defp broadcast({:ok, setting} = result) do
    Phoenix.PubSub.broadcast(Hermes.PubSub, "settings", {:settings_changed, setting})
    result
  end

  defp broadcast(error), do: error

  @doc """
  Stores or removes the logo. It is not part of the normal settings form, so
  it gets its own function instead of a changeset field.
  """
  def put_logo(data, content_type) do
    updated_at = if data, do: DateTime.utc_now() |> DateTime.truncate(:second)

    get()
    |> Ecto.Changeset.change(%{
      logo_data: data,
      logo_content_type: content_type,
      logo_updated_at: updated_at
    })
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking settings changes.
  """
  def change(%Setting{} = setting, attrs \\ %{}) do
    Setting.changeset(setting, attrs)
  end

  @doc """
  File name for the vCard, derived from the display name: everyone recognises
  "bereitschaft.vcf" in their downloads, "hermes-kontakt.vcf" says nothing.
  """
  def vcard_filename(%Setting{clip_display_name: name}) do
    slug =
      name
      |> to_string()
      |> String.downcase()
      |> String.replace("ä", "ae")
      |> String.replace("ö", "oe")
      |> String.replace("ü", "ue")
      |> String.replace("ß", "ss")
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")

    case slug do
      "" -> "kontakt.vcf"
      slug -> slug <> ".vcf"
    end
  end

  @doc """
  Builds the vCard every on-duty person imports once, so forwarded calls show
  `clip_display_name` on their phone. Returns `{:error, :no_clip_number}` until
  the number is configured.
  """
  def vcard(%Setting{clip_number: nil}), do: {:error, :no_clip_number}

  def vcard(%Setting{clip_number: number, clip_display_name: name}) do
    name = escape_vcard(name)

    card =
      [
        "BEGIN:VCARD",
        "VERSION:3.0",
        "N:#{name};;;;",
        "FN:#{name}",
        "TEL;TYPE=WORK,VOICE:#{number}",
        "END:VCARD"
      ]
      |> Enum.join("\r\n")

    {:ok, card <> "\r\n"}
  end

  defp escape_vcard(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace(~r/[,;]/, &("\\" <> &1))
    |> String.replace(~r/\r?\n/, "\\n")
  end
end
