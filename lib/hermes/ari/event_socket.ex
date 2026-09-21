defmodule Hermes.Ari.EventSocket do
  @moduledoc """
  WebSocket connection to `/ari/events`, over which Asterisk reports everything
  that happens on a call. Reconnects on its own with exponential backoff; the
  connection state is published (see `Hermes.Ari.subscribe/0`).
  """
  use Fresh

  require Logger

  alias Hermes.Ari
  alias Hermes.Calls

  @doc """
  Child spec for the application supervisor. Returns `:ignore` when ARI is not
  configured (tests, development without a PBX).
  """
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link_if_enabled, []},
      restart: :permanent
    }
  end

  def start_link_if_enabled do
    if Ari.enabled?() do
      start_link(
        uri: uri(),
        state: %{},
        opts: [
          name: {:local, __MODULE__},
          ping_interval: 30_000,
          backoff_initial: 500,
          backoff_max: 30_000
        ]
      )
    else
      Logger.info("ARI event socket disabled (no credentials configured)")
      :ignore
    end
  end

  @doc """
  The websocket URL including credentials and the Stasis app to subscribe to.
  """
  def uri do
    base = URI.parse(Ari.config(:base_url, "http://127.0.0.1:8088"))
    scheme = if base.scheme == "https", do: "wss", else: "ws"

    query =
      URI.encode_query(
        app: Ari.app_name(),
        subscribeAll: "true",
        api_key: "#{Ari.config(:username)}:#{Ari.config(:password)}"
      )

    %URI{base | scheme: scheme, path: "/ari/events", query: query} |> URI.to_string()
  end

  @impl true
  def handle_connect(_status, _headers, state) do
    Logger.info("ARI event socket connected")
    Ari.put_status(:connected)
    {:ok, state}
  end

  @impl true
  def handle_in({:text, payload}, state) do
    case Jason.decode(payload) do
      {:ok, event} ->
        Calls.handle_event(event)

      {:error, _} ->
        Logger.warning("ARI event socket received a non-JSON frame")
    end

    {:ok, state}
  end

  def handle_in(_frame, state), do: {:ok, state}

  @impl true
  def handle_disconnect(code, reason, state) do
    Logger.warning("ARI event socket disconnected (#{inspect(code)} #{inspect(reason)})")
    Ari.put_status(:disconnected)
    {:reconnect, state}
  end

  @impl true
  def handle_error(error, state) do
    Logger.warning("ARI event socket error: #{inspect(error)}")
    Ari.put_status(:disconnected)
    {:reconnect, state}
  end

  @impl true
  def handle_terminate(reason, _state) do
    Logger.info("ARI event socket terminated: #{inspect(reason)}")
    Ari.put_status(:disconnected)
  end
end
