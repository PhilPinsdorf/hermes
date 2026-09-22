defmodule Hermes.Branding do
  @moduledoc """
  How this installation presents itself: name, accent colour and logo.

  One deployment belongs to one customer, so the appearance is part of the
  settings rather than a build-time constant. The logo lives in the database,
  which means a database backup restores the whole appearance with it.

  The accents are a fixed, muted set. A free colour picker would sooner or
  later produce something unreadable on one of the two themes.
  """

  alias Hermes.Settings

  # Accent colours as OKLCH, one value per theme, plus a readable text colour
  # on top of it.
  @accents %{
    slate: %{
      label: "Schiefer",
      light: "oklch(45% 0.04 250)",
      dark: "oklch(72% 0.05 250)",
      on_light: "oklch(98% 0.005 250)",
      on_dark: "oklch(20% 0.02 250)",
      swatch: "#475569"
    },
    blue: %{
      label: "Blau",
      light: "oklch(50% 0.13 250)",
      dark: "oklch(72% 0.12 250)",
      on_light: "oklch(98% 0.01 250)",
      on_dark: "oklch(20% 0.03 250)",
      swatch: "#2563eb"
    },
    teal: %{
      label: "Petrol",
      light: "oklch(48% 0.09 195)",
      dark: "oklch(72% 0.09 195)",
      on_light: "oklch(98% 0.01 195)",
      on_dark: "oklch(20% 0.02 195)",
      swatch: "#0d9488"
    },
    green: %{
      label: "Grün",
      light: "oklch(48% 0.1 150)",
      dark: "oklch(72% 0.1 150)",
      on_light: "oklch(98% 0.01 150)",
      on_dark: "oklch(20% 0.02 150)",
      swatch: "#15803d"
    },
    amber: %{
      label: "Bernstein",
      light: "oklch(55% 0.12 75)",
      dark: "oklch(75% 0.12 75)",
      on_light: "oklch(99% 0.01 75)",
      on_dark: "oklch(22% 0.03 75)",
      swatch: "#b45309"
    },
    rose: %{
      label: "Altrosa",
      light: "oklch(50% 0.12 15)",
      dark: "oklch(72% 0.11 15)",
      on_light: "oklch(98% 0.01 15)",
      on_dark: "oklch(20% 0.03 15)",
      swatch: "#be123c"
    }
  }

  @default_name "Hermes"

  @doc """
  Everything a page needs to present this installation, read in one go.
  """
  def summary(settings \\ nil) do
    settings = settings || Settings.get()

    %{
      name: name(settings),
      accent: settings.accent,
      accent_css: accent_css(settings),
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

  @doc "All selectable accents as `{label, value}`."
  def accent_options do
    for {value, %{label: label}} <- @accents, do: {label, value}
  end

  @doc "A colour sample for the settings page."
  def swatch(accent), do: accent_info(accent).swatch

  @doc """
  CSS for the chosen accent: overrides daisyUI's primary colour for both
  themes. Rendered into the page head, so the accent applies before anything
  is painted (no flash of the default colour).
  """
  def accent_css(settings \\ nil) do
    info = (settings || Settings.get()).accent |> accent_info()

    """
    :root, [data-theme="light"] {
      --color-primary: #{info.light};
      --color-primary-content: #{info.on_light};
    }
    @media (prefers-color-scheme: dark) {
      :root:not([data-theme="light"]) {
        --color-primary: #{info.dark};
        --color-primary-content: #{info.on_dark};
      }
    }
    [data-theme="dark"] {
      --color-primary: #{info.dark};
      --color-primary-content: #{info.on_dark};
    }
    """
  end

  defp accent_info(accent), do: Map.get(@accents, accent, @accents.slate)

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
