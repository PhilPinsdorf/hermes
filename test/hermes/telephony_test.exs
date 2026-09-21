defmodule Hermes.TelephonyTest do
  use Hermes.DataCase, async: true

  alias Hermes.Settings
  alias Hermes.Telephony

  test "dials German numbers nationally through the Fritz!Box" do
    assert Telephony.endpoint_for("+491711234567") == "PJSIP/01711234567@fritzbox"
  end

  test "dials foreign numbers with the international prefix" do
    assert Telephony.endpoint_for("+436641234567") == "PJSIP/00436641234567@fritzbox"
  end

  test "dials an internal extension of the Fritz!Box directly" do
    assert Telephony.endpoint_for("**621") == "PJSIP/**621@fritzbox"
  end

  test "the caller id is the configured CLIP number" do
    assert Telephony.caller_id() == nil

    {:ok, _} = Settings.update(%{clip_number: "030 1234567"})
    assert Telephony.caller_id() == "+49301234567"
  end

  test "the channel budget comes from the settings" do
    assert Telephony.max_concurrent_legs() == 2

    {:ok, _} = Settings.update(%{max_external_channels: 6})
    assert Telephony.max_concurrent_legs() == 6
  end
end
