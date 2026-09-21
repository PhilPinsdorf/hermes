defmodule Hermes.SettingsTest do
  use Hermes.DataCase, async: true

  alias Hermes.Settings
  alias Hermes.Settings.Setting

  describe "get/0" do
    test "creates the singleton row with defaults on first access" do
      assert %Setting{id: 1} = setting = Settings.get()
      assert setting.clip_number == nil
      assert setting.clip_display_name == "Bereitschaft"
      assert setting.ring_timeout_seconds == 25
      assert setting.ring_strategy == :sequential
      assert setting.max_external_channels == 2
      assert setting.busy_policy == :announce
    end

    test "returns the same row on later calls" do
      Settings.get()
      assert Repo.aggregate(Setting, :count) == 1
      assert %Setting{id: 1} = Settings.get()
      assert Repo.aggregate(Setting, :count) == 1
    end

    test "the database refuses a second row" do
      Settings.get()

      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%Setting{id: 2})
      end
    end
  end

  describe "update/1" do
    test "normalizes the CLIP number" do
      assert {:ok, setting} = Settings.update(%{clip_number: "030 1234567"})
      assert setting.clip_number == "+49301234567"
    end

    test "the displayed number may not be an internal extension" do
      assert {:error, changeset} = Settings.update(%{clip_number: "**621"})
      assert errors_on(changeset).clip_number == ["darf keine interne Nebenstelle sein"]
    end

    test "validates ranges" do
      assert {:error, changeset} =
               Settings.update(%{
                 ring_timeout_seconds: 1,
                 max_external_channels: 1,
                 ring_strategy: "wild"
               })

      errors = errors_on(changeset)
      assert errors.ring_timeout_seconds != []
      assert errors.max_external_channels != []
      assert errors.ring_strategy == ["is invalid"]
    end

    test "a blanked display name falls back to the default" do
      {:ok, _} = Settings.update(%{clip_display_name: "Notdienst"})
      assert {:ok, setting} = Settings.update(%{clip_display_name: "  "})
      assert setting.clip_display_name == "Bereitschaft"
    end

    test "trims the display name" do
      assert {:ok, %{clip_display_name: "Notdienst"}} =
               Settings.update(%{clip_display_name: "  Notdienst "})
    end
  end

  describe "vcard_filename/1" do
    test "follows the display name" do
      assert Settings.vcard_filename(%Setting{clip_display_name: "Bereitschaft"}) ==
               "bereitschaft.vcf"

      assert Settings.vcard_filename(%Setting{clip_display_name: "Notdienst Süd"}) ==
               "notdienst-sued.vcf"

      assert Settings.vcard_filename(%Setting{clip_display_name: "Praxis Dr. Müller"}) ==
               "praxis-dr-mueller.vcf"
    end

    test "falls back when the name has nothing usable" do
      assert Settings.vcard_filename(%Setting{clip_display_name: "***"}) == "kontakt.vcf"
      assert Settings.vcard_filename(%Setting{clip_display_name: nil}) == "kontakt.vcf"
    end
  end

  describe "vcard/1" do
    test "needs a CLIP number" do
      assert Settings.vcard(%Setting{clip_number: nil}) == {:error, :no_clip_number}
    end

    test "builds a vCard 3.0 with CRLF line endings" do
      {:ok, card} =
        Settings.vcard(%Setting{clip_number: "+49301234567", clip_display_name: "Bereitschaft"})

      assert card ==
               "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Bereitschaft;;;;\r\nFN:Bereitschaft\r\n" <>
                 "TEL;TYPE=WORK,VOICE:+49301234567\r\nEND:VCARD\r\n"
    end

    test "escapes special characters in the name" do
      {:ok, card} =
        Settings.vcard(%Setting{clip_number: "+49301234567", clip_display_name: "Dienst; A, B"})

      assert card =~ "FN:Dienst\\; A\\, B\r\n"
    end
  end
end
