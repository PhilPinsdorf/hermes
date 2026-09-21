defmodule Hermes.Telephony.Trunk do
  @moduledoc """
  How calls reach the outside world.

  Today that is the Fritz!Box; a SIP trunk (sipgate, easybell, Placetel …)
  would be a second implementation of this behaviour and nothing else in
  Hermes would have to change.
  """

  @doc "Asterisk endpoint that dials `number` (E.164)."
  @callback endpoint_for(number :: String.t()) :: String.t()

  @doc "Number shown on the called phone, or `nil` when not configured yet."
  @callback caller_id() :: String.t() | nil

  @doc "How many external calls the line allows at the same time."
  @callback max_concurrent_legs() :: pos_integer()
end
