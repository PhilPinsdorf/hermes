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
  def caller_id, do: Settings.get().clip_number

  @impl true
  def max_concurrent_legs, do: Settings.get().max_external_channels
end
