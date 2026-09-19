defmodule Hermes.DirectoryFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Hermes.Directory` context.
  """

  def unique_phone_number do
    # 9 random digits after a mobile prefix: +49 170 xxxxxxxxx
    suffix = System.unique_integer([:positive]) |> rem(1_000_000_000)
    "+49170" <> String.pad_leading(Integer.to_string(suffix), 9, "0")
  end

  def valid_person_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Person #{System.unique_integer([:positive])}",
      phone_e164: unique_phone_number()
    })
  end

  def person_fixture(attrs \\ %{}) do
    {:ok, person} =
      attrs
      |> valid_person_attributes()
      |> Hermes.Directory.create_person()

    person
  end
end
