defmodule HermesWeb.SettingsLiveTest do
  use HermesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Hermes.Settings

  setup :register_and_log_in_user

  test "requires login" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/settings")
  end

  test "shows defaults and explains the line limit", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/settings")

    assert html =~ "Bereitschaft"
    assert html =~ "Besetztzeichen des Providers"
    refute html =~ "Kontakt herunterladen"
  end

  test "saves settings and offers the vCard afterwards", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings")

    html =
      lv
      |> form("#settings-form",
        setting: %{
          clip_number: "030 1234567",
          clip_display_name: "Notdienst",
          ring_timeout_seconds: 30,
          ring_strategy: "sequential",
          max_external_channels: 4
        }
      )
      |> render_submit()

    assert html =~ "Einstellungen gespeichert."
    assert html =~ "Kontakt herunterladen"
    assert html =~ "+49 301234567"

    setting = Settings.get()
    assert setting.clip_number == "+49301234567"
    assert setting.clip_display_name == "Notdienst"
    assert setting.max_external_channels == 4
  end

  test "renders validation errors", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings")

    html =
      lv
      |> form("#settings-form", setting: %{clip_number: "12345", ring_timeout_seconds: 1})
      |> render_change()

    assert html =~ "braucht eine Vorwahl"
    assert html =~ "muss größer oder gleich 5 sein"
  end

  test "warns that simultaneous ringing degrades on a 2-channel line", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings")

    html =
      lv
      |> form("#settings-form",
        setting: %{ring_strategy: "simultaneous", max_external_channels: 2}
      )
      |> render_change()

    assert html =~ ~s(id="simultaneous-hint")

    html =
      lv
      |> form("#settings-form",
        setting: %{ring_strategy: "simultaneous", max_external_channels: 4}
      )
      |> render_change()

    refute html =~ ~s(id="simultaneous-hint")
  end

  describe "announcements" do
    test "offers a player and a text field per announcement", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      for name <- Hermes.Sounds.names() do
        assert has_element?(lv, "#player-#{name}")
        assert has_element?(lv, "#text-form-#{name}")
      end
    end

    test "the player is served inline, not as a download", %{conn: conn} do
      {:ok, _} = Hermes.Sounds.install_defaults()

      conn = get(conn, ~p"/settings/announcements/confirm")

      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") |> hd() =~ "audio/wav"
      assert get_resp_header(conn, "content-disposition") == ["inline"]
    end

    test "an unknown announcement leads back to the settings", %{conn: conn} do
      conn = get(conn, ~p"/settings/announcements/does-not-exist")
      assert redirected_to(conn) == ~p"/settings"
    end

    test "saving a text only changes that one text", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      lv
      |> form("#text-form-confirm", setting: %{text_confirm: "Bitte die 1 drücken."})
      |> render_submit()

      setting = Hermes.Settings.get()
      assert setting.text_confirm == "Bitte die 1 drücken."
      assert setting.text_all_busy == nil
    end
  end

  describe "call log retention" do
    test "can be configured", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      lv
      |> form("#retention-form",
        setting: %{call_log_retention_days: 30, call_log_anonymize_after_days: 7}
      )
      |> render_submit()

      setting = Hermes.Settings.get()
      assert setting.call_log_retention_days == 30
      assert setting.call_log_anonymize_after_days == 7
    end

    test "anonymizing later than deleting is rejected", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      html =
        lv
        |> form("#retention-form",
          setting: %{call_log_retention_days: 30, call_log_anonymize_after_days: 30}
        )
        |> render_submit()

      assert html =~ "muss kleiner als die Aufbewahrungsdauer sein"
    end
  end

  describe "appearance" do
    test "the name can be changed and shows up in the header", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      html =
        lv
        |> form("#branding-form", setting: %{brand_name: "Notdienst Süd"})
        |> render_submit()

      assert html =~ "Notdienst Süd"
      assert Hermes.Settings.get().brand_name == "Notdienst Süd"
    end

    test "a name that is too short is rejected", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      html = lv |> form("#branding-form", setting: %{brand_name: "X"}) |> render_submit()

      assert html =~ "muss mindestens 2 Zeichen lang sein"
      assert Hermes.Settings.get().brand_name == "Hermes"
    end

    test "the logo is offered for upload and can be removed", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      assert has_element?(lv, "#logo-form")
      refute has_element?(lv, "#logo-form button", "Logo entfernen")

      {:ok, _} = Hermes.Settings.put_logo("fake-png", "image/png")
      {:ok, lv, _html} = live(conn, ~p"/settings")
      assert has_element?(lv, "#logo-form button", "Logo entfernen")

      lv |> element("#logo-form button", "Logo entfernen") |> render_click()
      refute Hermes.Branding.logo?()
    end
  end

  describe "logo delivery" do
    test "is served with its content type", %{conn: conn} do
      {:ok, _} = Hermes.Settings.put_logo("fake-png", "image/png")

      conn = get(conn, ~p"/branding/logo")

      assert response(conn, 200) == "fake-png"
      assert get_resp_header(conn, "content-type") |> hd() =~ "image/png"
    end

    test "answers with 404 while no logo was uploaded", %{conn: conn} do
      conn = get(conn, ~p"/branding/logo")
      assert conn.status == 404
    end
  end

  describe "page head" do
    test "carries the name of the installation", %{conn: conn} do
      {:ok, _} = Hermes.Settings.update(%{brand_name: "Notdienst"})

      html = conn |> get(~p"/settings") |> html_response(200)

      assert html =~ "· Notdienst"
    end

    test "carries a favicon even without an uploaded logo", %{conn: conn} do
      html = conn |> get(~p"/settings") |> html_response(200)

      assert html =~ ~s(rel="icon" href="/favicon.svg")
      assert html =~ ~s(rel="icon" href="/favicon.ico")
      refute html =~ "/branding/logo"
    end

    test "the uploaded logo becomes the favicon", %{conn: conn} do
      {:ok, _} = Hermes.Settings.put_logo("fake-png", "image/png")

      html = conn |> get(~p"/settings") |> html_response(200)

      assert html =~ ~s(rel="icon" href="/branding/logo?v=)
      # Only one icon, otherwise the browser may pick the wrong one.
      refute html =~ "/favicon.svg"
    end
  end
end
