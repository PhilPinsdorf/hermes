defmodule Hermes.Telephony.Trunk.FritzBox do
  @moduledoc """
  Calls go out through the Fritz!Box, over the same SIP account Asterisk is
  registered with (see `asterisk/etc/pjsip.conf`).

  The Fritz!Box expects the number the way a phone would dial it, not E.164.
  """

  @behaviour Hermes.Telephony.Trunk

  alias Hermes.Directory.PhoneNumber
  alias Hermes.Settings

  @endpoint "fritzbox"

  @impl true
  def endpoint_for(number) do
    "PJSIP/" <> PhoneNumber.to_dialable(number) <> "@" <> @endpoint
  end

  @impl true
  def caller_id do
    # Deliberately nothing: the Fritz!Box decides which number goes out, based
    # on the IP phone's "Ausgehende Anrufe" setting, and it recognises the call
    # by the SIP user name (from_user in pjsip.conf). Putting a number in the
    # From header instead makes the Fritz!Box send the call anonymously — the
    # called person then sees "unbekannt" instead of the landline number.
    #
    # `clip_number` in the settings therefore only describes what the Fritz!Box
    # sends; it is what the vCard hands out.
    nil
  end

  @impl true
  def max_concurrent_legs, do: Settings.get().max_external_channels
end
