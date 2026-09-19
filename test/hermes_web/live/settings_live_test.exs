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
end
