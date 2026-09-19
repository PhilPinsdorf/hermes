defmodule Hermes.Directory.PhoneNumber do
  @moduledoc """
  Normalizes phone numbers as people type them in Germany into E.164
  (`+491711234567`), which is what we store and what Asterisk dials.

  Accepted input forms:

    * international: `+49 171 1234567`, `+49 (0) 171 1234567`, `0049 171 1234567`
    * national with area/mobile prefix: `0171 1234567`, `030/1234567`
    * common separators: spaces, `-`, `/`, `.`, parentheses

  A number without a leading `0` or `+` (a local number without area code)
  is rejected, since we cannot know which area it belongs to.
  """

  @default_country_code "49"

  @e164 ~r/^\+[1-9]\d{6,14}$/

  @doc """
  Normalizes `input` to E.164.

  ## Examples

      iex> normalize("0171 1234567")
      {:ok, "+491711234567"}

      iex> normalize("+49 (0) 30 / 123 456")
      {:ok, "+4930123456"}

      iex> normalize("1234567")
      {:error, :missing_prefix}

  """
  @spec normalize(String.t() | nil) ::
          {:ok, String.t()} | {:error, :blank | :invalid_characters | :missing_prefix | :invalid}
  def normalize(nil), do: {:error, :blank}

  def normalize(input) when is_binary(input) do
    cleaned =
      input
      |> String.trim()
      # "+49 (0) 171..." is a widespread German notation; the (0) must be dropped.
      |> String.replace(~r/\(\s*0\s*\)/, "")
      |> String.replace(~r/[\s\-\/\.\(\)]/u, "")

    cond do
      cleaned == "" -> {:error, :blank}
      not Regex.match?(~r/^\+?\d+$/, cleaned) -> {:error, :invalid_characters}
      true -> cleaned |> to_international() |> validate()
    end
  end

  # "+49 0171 ..." / "0049 0171 ...": the trunk prefix 0 must not follow the country code.
  defp to_international("+490" <> rest), do: {:ok, "+49" <> rest}
  defp to_international("00490" <> rest), do: {:ok, "+49" <> rest}
  defp to_international("+" <> _ = number), do: {:ok, number}
  defp to_international("00" <> rest), do: {:ok, "+" <> rest}
  defp to_international("0" <> rest), do: {:ok, "+" <> @default_country_code <> rest}
  defp to_international(_), do: {:error, :missing_prefix}

  defp validate({:ok, number}) do
    if Regex.match?(@e164, number), do: {:ok, number}, else: {:error, :invalid}
  end

  defp validate(error), do: error

  @doc """
  Human readable error message for a failed `normalize/1`.
  """
  @spec error_message(atom()) :: String.t()
  def error_message(:blank), do: "darf nicht leer sein"
  def error_message(:invalid_characters), do: "enthält ungültige Zeichen"

  def error_message(:missing_prefix),
    do: "braucht eine Vorwahl (z. B. 0171 … oder +49 171 …)"

  def error_message(:invalid), do: "ist keine gültige Telefonnummer"

  @doc """
  Ecto changeset helper: normalizes `field` in place or adds an error.
  """
  @spec validate_change(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_change(changeset, field) do
    case Ecto.Changeset.get_change(changeset, field) do
      nil ->
        changeset

      value ->
        case normalize(value) do
          {:ok, e164} -> Ecto.Changeset.put_change(changeset, field, e164)
          {:error, reason} -> Ecto.Changeset.add_error(changeset, field, error_message(reason))
        end
    end
  end

  @doc """
  Formats an E.164 number for display, e.g. `+49 171 1234567`.
  Only the country code is split off; German area codes vary in length.
  """
  @spec format(String.t() | nil) :: String.t()
  def format(nil), do: ""
  def format("+49" <> rest), do: "+49 " <> rest
  def format(number), do: number
end
