defmodule Hermes.Branding do
  @moduledoc """
  How this installation presents itself: name and logo.

  One deployment belongs to one customer, so the appearance is part of the
  settings rather than a build-time constant. The logo lives in the database,
  which means a database backup restores the whole appearance with it.

  The colours are not part of it: the palette is fixed in `assets/css/app.css`,
  so every installation looks the same and no setting can produce a combination
  that is unreadable on one of the two themes.
  """

  alias Hermes.Settings

  @default_name "Hermes"

  @doc """
  Everything a page needs to present this installation, read in one go.
  """
  def summary(settings \\ nil) do
    settings = settings || Settings.get()

    %{
      name: name(settings),
      logo?: logo?(settings),
      logo_version: logo_version(settings)
    }
  end

  @doc "Name of this installation, e.g. in the header and the browser tab."
  def name(settings \\ nil) do
    case settings || Settings.get() do
      %{brand_name: name} when is_binary(name) ->
        case String.trim(name) do
          "" -> @default_name
          name -> name
        end

      _ ->
        @default_name
    end
  end

  ## Logo

  @doc "Whether a logo was uploaded."
  def logo?(settings \\ nil) do
    settings = settings || Settings.get()
    is_binary(settings.logo_data) and settings.logo_data != ""
  end

  @doc """
  Version marker for the logo URL, so browsers pick up a new logo but can
  still cache the old one.
  """
  def logo_version(settings \\ nil) do
    case (settings || Settings.get()).logo_updated_at do
      %DateTime{} = at -> DateTime.to_unix(at)
      _ -> 0
    end
  end

  @doc """
  Stores an uploaded logo. Only formats browsers show inline are accepted.
  """
  def put_logo(path, content_type) do
    with :ok <- validate_content_type(content_type),
         {:ok, data} <- File.read(path),
         :ok <- validate_size(data) do
      Settings.put_logo(data, content_type)
    end
  end

  @doc "Removes the logo again."
  def remove_logo, do: Settings.put_logo(nil, nil)

  defp validate_content_type(type) when type in ~w(image/png image/jpeg image/svg+xml image/webp),
    do: :ok

  defp validate_content_type(_type), do: {:error, :unsupported_format}

  defp validate_size(data) when byte_size(data) <= 1_000_000, do: :ok
  defp validate_size(_data), do: {:error, :too_large}
end
