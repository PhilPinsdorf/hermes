defmodule Hermes.SoundsTest do
  use Hermes.DataCase, async: false

  alias Hermes.Settings
  alias Hermes.Sounds

  setup do
    dir = Path.join(System.tmp_dir!(), "hermes-sounds-#{System.unique_integer([:positive])}")
    original = Application.get_env(:hermes, :sounds_dir)
    Application.put_env(:hermes, :sounds_dir, dir)

    on_exit(fn ->
      Application.put_env(:hermes, :sounds_dir, original)
      File.rm_rf(dir)
    end)

    %{dir: dir}
  end

  describe "paths" do
    test "media/1 is an ARI sound URI without file extension", %{dir: dir} do
      assert Sounds.media(:no_one_on_duty) == "sound:#{dir}/no-one-on-duty"
      assert Sounds.file(:no_one_on_duty) == "#{dir}/no-one-on-duty.wav"
    end
  end

  describe "install_defaults/0" do
    test "creates the directory and copies the announcements", %{dir: dir} do
      assert {:ok, copied} = Sounds.install_defaults()
      assert Enum.sort(copied) == Enum.sort(Sounds.names())

      for name <- Sounds.names() do
        assert File.exists?(Path.join(dir, Path.basename(Sounds.file(name))))
      end
    end

    test "never overwrites an existing announcement" do
      {:ok, _} = Sounds.install_defaults()
      File.write!(Sounds.file(:no_one_on_duty), "self-recorded")

      assert {:ok, []} = Sounds.install_defaults()
      assert File.read!(Sounds.file(:no_one_on_duty)) == "self-recorded"
    end

    test "the shipped announcements are 8 kHz, 16 bit, mono WAV" do
      {:ok, _} = Sounds.install_defaults()

      for name <- Sounds.names() do
        <<"RIFF", _size::little-32, "WAVE", "fmt ", 16::little-32, 1::little-16,
          channels::little-16, sample_rate::little-32, _byte_rate::little-32,
          _block_align::little-16, bits::little-16, _rest::binary>> =
          File.read!(Sounds.file(name))

        assert {channels, sample_rate, bits} == {1, 8000, 16}
      end
    end
  end

  describe "texts" do
    test "fall back to the defaults" do
      assert Sounds.text(:confirm) == Sounds.default_text(:confirm)
      assert Sounds.text(:confirm) =~ "Zum Annehmen die 1"
    end

    test "come from the settings when set" do
      {:ok, _} = Settings.update(%{text_confirm: "  Bitte die 1 drücken.  "})
      assert Sounds.text(:confirm) == "Bitte die 1 drücken."
    end

    test "an emptied text falls back to the default" do
      {:ok, _} = Settings.update(%{text_all_busy: "Alles belegt."})
      {:ok, _} = Settings.update(%{text_all_busy: ""})
      assert Sounds.text(:all_busy) == Sounds.default_text(:all_busy)
    end
  end

  describe "refresh/1 without speech synthesis" do
    test "keeps the existing announcement and does not fail" do
      {:ok, _} = Sounds.install_defaults()
      {:ok, setting} = Settings.update(%{text_confirm: "Ein neuer Text."})

      assert Sounds.refresh(setting) == []
      assert File.exists?(Sounds.file(:confirm))
    end

    test "installs the shipped announcement when nothing is there yet" do
      {:ok, setting} = Settings.update(%{text_confirm: "Ein neuer Text."})

      assert Sounds.refresh(setting) == []
      assert File.exists?(Sounds.file(:confirm))
      # Marked as shipped, so speech synthesis replaces it as soon as it exists.
      assert Sounds.shipped?(:confirm)
    end
  end

  describe "uploads" do
    test "an uploaded file wins over the text and survives a refresh", %{dir: dir} do
      {:ok, _} = Sounds.install_defaults()
      source = Path.join(dir, "upload-source.wav")
      File.cp!(Sounds.file(:confirm), source)

      # sox may be missing in development; then the upload is simply rejected.
      case Sounds.install_upload(:confirm, source) do
        :ok ->
          assert Sounds.uploaded?(:confirm)
          {:ok, setting} = Settings.update(%{text_confirm: "Anderer Text."})
          assert Sounds.refresh(setting) == []
          assert Sounds.uploaded?(:confirm)

          Sounds.reset(:confirm)
          refute Sounds.uploaded?(:confirm)

        {:error, :unavailable} ->
          assert Sounds.uploaded?(:confirm) == false
      end
    end
  end

  describe "announcement with the next shift" do
    setup do
      {:ok, setting} = Settings.update(%{announce_next_shift: true})
      %{setting: setting}
    end

    test "names the day and the time", %{setting: setting} do
      today = DateTime.utc_now() |> Hermes.Schedule.local_naive() |> NaiveDateTime.to_date()

      tomorrow_at_8 =
        today
        |> Date.add(1)
        |> DateTime.new!(~T[08:00:00], Hermes.Schedule.time_zone())

      text = Sounds.next_shift_text(tomorrow_at_8, setting)
      assert text =~ "Ab morgen um 8 Uhr sind wir wieder erreichbar."
      assert text =~ Sounds.text(:no_one_on_duty, setting)
    end

    test "says the minutes when there are any", %{setting: setting} do
      today = DateTime.utc_now() |> Hermes.Schedule.local_naive() |> NaiveDateTime.to_date()
      at = DateTime.new!(today, ~T[17:30:00], Hermes.Schedule.time_zone())

      assert Sounds.next_shift_text(at, setting) =~ "Ab heute um 17 Uhr 30"
    end

    test "stays silent about changes more than a week away", %{setting: setting} do
      in_two_weeks = DateTime.add(DateTime.utc_now(), 14, :day)
      assert Sounds.next_shift_text(in_two_weeks, setting) == nil
    end

    test "falls back to the plain announcement while no variant exists", %{setting: setting} do
      at = DateTime.add(DateTime.utc_now(), 1, :day)
      person = %Hermes.Directory.Person{id: 1, name: "Anna"}

      assert Sounds.no_one_on_duty_media({at, [person]}, setting) ==
               Sounds.media(:no_one_on_duty)
    end

    test "uses the variant once it has been generated", %{dir: dir, setting: setting} do
      at = DateTime.add(DateTime.utc_now(), 1, :day)
      person = %Hermes.Directory.Person{id: 1, name: "Anna"}
      text = Sounds.next_shift_text(at, setting)

      # Pretend the background generation already finished.
      hash = :crypto.hash(:sha256, text) |> Base.encode16(case: :lower) |> binary_part(0, 16)
      File.mkdir_p!(Path.join(dir, "variants"))
      variant = Path.join([dir, "variants", "no-one-on-duty-#{hash}.wav"])
      File.write!(variant, "audio")

      assert Sounds.no_one_on_duty_media({at, [person]}, setting) ==
               "sound:" <> String.replace_suffix(variant, ".wav", "")
    end

    test "is switched off by the setting" do
      {:ok, setting} = Settings.update(%{announce_next_shift: false})
      at = DateTime.add(DateTime.utc_now(), 1, :day)
      person = %Hermes.Directory.Person{id: 1, name: "Anna"}

      assert Sounds.no_one_on_duty_media({at, [person]}, setting) == Sounds.media(:no_one_on_duty)
    end
  end

  describe "prune_variants/1" do
    test "removes only old variants", %{dir: dir} do
      variants = Path.join(dir, "variants")
      File.mkdir_p!(variants)

      old = Path.join(variants, "old.wav")
      fresh = Path.join(variants, "fresh.wav")
      File.write!(old, "x")
      File.write!(fresh, "x")

      long_ago = System.os_time(:second) - 60 * 86_400
      File.touch!(old, long_ago)

      assert Sounds.prune_variants(30) == 1
      refute File.exists?(old)
      assert File.exists?(fresh)
    end

    test "copes with a missing directory" do
      assert Sounds.prune_variants(30) == 0
    end
  end
end
