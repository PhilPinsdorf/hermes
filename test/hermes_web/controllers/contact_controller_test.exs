defmodule HermesWeb.ContactControllerTest do
  use HermesWeb.ConnCase, async: true

  alias Hermes.Settings

  setup :register_and_log_in_user

  test "downloads the global vCard", %{conn: conn} do
    {:ok, _} = Settings.update(%{clip_number: "030 1234567", clip_display_name: "Bereitschaft"})

    conn = get(conn, ~p"/settings/contact.vcf")

    assert response(conn, 200) =~ "TEL;TYPE=WORK,VOICE:+49301234567"
    assert get_resp_header(conn, "content-type") |> hd() =~ "text/vcard"
    assert get_resp_header(conn, "content-disposition") |> hd() =~ "hermes-kontakt.vcf"
  end

  test "redirects to settings while no CLIP number is set", %{conn: conn} do
    conn = get(conn, ~p"/settings/contact.vcf")

    assert redirected_to(conn) == ~p"/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Rufnummer"
  end

  test "requires login" do
    conn = get(build_conn(), ~p"/settings/contact.vcf")
    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
