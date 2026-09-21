defmodule Hermes.Ari do
  @moduledoc """
  Access to Asterisk: configuration, the configured client implementation and
  the connection state of the event socket.
  """

  @behaviour Hermes.Ari.Client

  @topic "ari"

  @doc """
  Configuration of the ARI connection (`config :hermes, Hermes.Ari, ...`).
  """
  def config, do: Application.get_env(:hermes, __MODULE__, [])

  def config(key, default \\ nil), do: Keyword.get(config(), key, default)

  @doc "The Stasis application name Asterisk hands calls to."
  def app_name, do: config(:app, "hermes")

  @doc "Whether the event socket should run (off in tests and without credentials)."
  def enabled?, do: config(:enabled, false) and is_binary(config(:password))

  @doc "The client implementation in use (mocked in tests)."
  def client, do: Application.get_env(:hermes, :ari_client, Hermes.Ari.Client.Http)

  @impl true
  def answer(channel_id), do: client().answer(channel_id)

  @impl true
  def play(channel_id, media), do: client().play(channel_id, media)

  @impl true
  def hangup(channel_id), do: client().hangup(channel_id)

  @impl true
  def ring(channel_id), do: client().ring(channel_id)

  @impl true
  def ring_stop(channel_id), do: client().ring_stop(channel_id)

  @impl true
  def create_channel(endpoint, channel_id, app_args),
    do: client().create_channel(endpoint, channel_id, app_args)

  @impl true
  def set_variable(channel_id, name, value), do: client().set_variable(channel_id, name, value)

  @impl true
  def dial(channel_id, timeout), do: client().dial(channel_id, timeout)

  @impl true
  def create_bridge(bridge_id), do: client().create_bridge(bridge_id)

  @impl true
  def add_to_bridge(bridge_id, channel_ids), do: client().add_to_bridge(bridge_id, channel_ids)

  @impl true
  def destroy_bridge(bridge_id), do: client().destroy_bridge(bridge_id)

  @impl true
  def endpoint(name), do: client().endpoint(name)

  @impl true
  def asterisk_info, do: client().asterisk_info()

  ## Connection state

  @doc """
  Subscribes to `{:ari_status, :connected | :disconnected}` messages.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Hermes.PubSub, @topic)
  end

  @doc "Current state of the event socket."
  def status, do: :persistent_term.get({__MODULE__, :status}, :disconnected)

  @doc false
  def put_status(status) when status in [:connected, :disconnected] do
    previous = status()
    :persistent_term.put({__MODULE__, :status}, status)

    if previous != status do
      :telemetry.execute([:hermes, :ari, status], %{system_time: System.system_time()}, %{})
      Phoenix.PubSub.broadcast(Hermes.PubSub, @topic, {:ari_status, status})
    end

    :ok
  end
end
