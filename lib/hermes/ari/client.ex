defmodule Hermes.Ari.Client do
  @moduledoc """
  Behaviour for the Asterisk REST Interface.

  Everything Hermes asks Asterisk to do goes through here, so call logic can be
  tested against a mock instead of a real PBX (see `Hermes.Ari.ClientMock`).

  Channel and bridge ids are the ones Asterisk assigns; media is given as an
  ARI media URI, e.g. `"sound:/var/lib/asterisk/sounds/hermes/no-one-on-duty"`.
  """

  @type channel_id :: String.t()
  @type playback_id :: String.t()
  @type reason :: {:http, pos_integer(), term()} | {:transport, term()}

  @doc "Answers a channel (the caller hears us from then on)."
  @callback answer(channel_id) :: :ok | {:error, reason}

  @doc """
  Plays media on a channel. Returns the playback id, which shows up again in
  the `PlaybackFinished` event.
  """
  @callback play(channel_id, media :: String.t()) :: {:ok, playback_id} | {:error, reason}

  @doc "Hangs up a channel."
  @callback hangup(channel_id) :: :ok | {:error, reason}

  @doc "Lets the caller hear ringback without answering their channel."
  @callback ring(channel_id) :: :ok | {:error, reason}

  @doc "Stops the ringback."
  @callback ring_stop(channel_id) :: :ok | {:error, reason}

  @doc """
  Creates an outgoing channel that stays under our control (it does not dial
  yet). `app_args` mark it as a leg of ours, so its `StasisStart` does not
  start a second call session.
  """
  @callback create_channel(endpoint :: String.t(), channel_id, app_args :: [String.t()]) ::
              {:ok, map()} | {:error, reason}

  @doc "Sets a channel variable, e.g. `CALLERID(num)`."
  @callback set_variable(channel_id, name :: String.t(), value :: String.t()) ::
              :ok | {:error, reason}

  @doc "Starts dialing a created channel; Asterisk gives up after `timeout` seconds."
  @callback dial(channel_id, timeout :: pos_integer()) :: :ok | {:error, reason}

  @doc "Creates a mixing bridge (caller and mobile phone meet in here)."
  @callback create_bridge(bridge_id :: String.t()) :: {:ok, map()} | {:error, reason}

  @doc "Adds channels to a bridge."
  @callback add_to_bridge(bridge_id :: String.t(), [channel_id]) :: :ok | {:error, reason}

  @doc "Destroys a bridge."
  @callback destroy_bridge(bridge_id :: String.t()) :: :ok | {:error, reason}

  @doc "Basic information about the connected Asterisk (used for diagnostics)."
  @callback asterisk_info() :: {:ok, map()} | {:error, reason}
end
