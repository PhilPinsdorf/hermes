defmodule Hermes.BrandingTest do
  use Hermes.DataCase, async: true

  alias Hermes.Branding
  alias Hermes.Settings

  describe "name/1" do
    test "defaults to Hermes" do
      assert Branding.name() == "Hermes"
    end

    test "follows the setting" do
      {:ok, setting} = Settings.update(%{brand_name: "Praxis Dr. Müller"})
      assert Branding.name(setting) == "Praxis Dr. Müller"
    end

    test "an empty name falls back" do
      assert Branding.name(%{brand_name: "   "}) == "Hermes"
      assert Branding.name(%{brand_name: nil}) == "Hermes"
    end
  end

  describe "logo" do
    @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82>>

    defp write_temp(content) do
      path = Path.join(System.tmp_dir!(), "logo-#{System.unique_integer([:positive])}")
      File.write!(path, content)
      on_exit(fn -> File.rm(path) end)
      path
    end

    test "is empty by default" do
      refute Branding.logo?()
      assert Branding.logo_version() == 0
    end

    test "is stored with its type and a version" do
      assert {:ok, _} = Branding.put_logo(write_temp(@png), "image/png")

      setting = Settings.get()
      assert Branding.logo?(setting)
      assert setting.logo_content_type == "image/png"
      assert Branding.logo_version(setting) > 0
    end

    test "rejects formats browsers would not show" do
      assert Branding.put_logo(write_temp("MZ"), "application/x-msdownload") ==
               {:error, :unsupported_format}

      refute Branding.logo?()
    end

    test "rejects oversized files" do
      big = write_temp(:binary.copy("x", 1_000_001))
      assert Branding.put_logo(big, "image/png") == {:error, :too_large}
    end

    test "can be removed again" do
      {:ok, _} = Branding.put_logo(write_temp(@png), "image/png")
      assert {:ok, _} = Branding.remove_logo()
      refute Branding.logo?()
    end
  end

  describe "summary/1" do
    test "carries everything a page needs" do
      {:ok, setting} = Settings.update(%{brand_name: "Notdienst"})
      summary = Branding.summary(setting)

      assert summary.name == "Notdienst"
      assert summary.logo? == false
    end
  end
end
