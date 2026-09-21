defmodule Hermes.Ari.Client.Http do
  @moduledoc """
  `Hermes.Ari.Client` over ARI's REST API.

  Errors are returned, never raised: a failing REST call must not take a call
  session down, it should lead to a clean hangup instead.
  """

  @behaviour Hermes.Ari.Client

  require Logger

  alias Hermes.Ari

  @impl true
  def answer(channel_id) do
    case request(:post, "/channels/#{channel_id}/answer") do
      {:ok, _body} -> :ok
      error -> error
    end
  end

  @impl true
  def play(channel_id, media) do
    playback_id = Ecto.UUID.generate()

    case request(:post, "/channels/#{channel_id}/play",
           media: media,
           playbackId: playback_id
         ) do
      {:ok, %{"id" => id}} -> {:ok, id}
      {:ok, _body} -> {:ok, playback_id}
      error -> error
    end
  end

  @impl true
  def hangup(channel_id) do
    case request(:delete, "/channels/#{channel_id}") do
      {:ok, _body} -> :ok
      # The channel is already gone; that is what we wanted anyway.
      {:error, {:http, 404, _}} -> :ok
      error -> error
    end
  end

  @impl true
  def ring(channel_id) do
    to_ok(request(:post, "/channels/#{channel_id}/ring"))
  end

  @impl true
  def ring_stop(channel_id) do
    to_ok(request(:delete, "/channels/#{channel_id}/ring"))
  end

  @impl true
  def create_channel(endpoint, channel_id, app_args) do
    request(:post, "/channels/create",
      endpoint: endpoint,
      app: Ari.app_name(),
      appArgs: Enum.join(app_args, ","),
      channelId: channel_id
    )
  end

  @impl true
  def set_variable(channel_id, name, value) do
    to_ok(request(:post, "/channels/#{channel_id}/variable", variable: name, value: value))
  end

  @impl true
  def dial(channel_id, timeout) do
    to_ok(request(:post, "/channels/#{channel_id}/dial", timeout: timeout))
  end

  @impl true
  def create_bridge(bridge_id) do
    request(:post, "/bridges", type: "mixing", bridgeId: bridge_id)
  end

  @impl true
  def add_to_bridge(bridge_id, channel_ids) do
    to_ok(
      request(:post, "/bridges/#{bridge_id}/addChannel", channel: Enum.join(channel_ids, ","))
    )
  end

  @impl true
  def destroy_bridge(bridge_id) do
    case request(:delete, "/bridges/#{bridge_id}") do
      {:ok, _body} -> :ok
      # already gone, which is what we wanted
      {:error, {:http, 404, _}} -> :ok
      error -> error
    end
  end

  @impl true
  def asterisk_info do
    request(:get, "/asterisk/info")
  end

  defp to_ok({:ok, _body}), do: :ok
  defp to_ok(error), do: error

  defp request(method, path, params \\ []) do
    options =
      [
        method: method,
        base_url: Ari.config(:base_url),
        url: "/ari" <> path,
        auth: {:basic, "#{Ari.config(:username)}:#{Ari.config(:password)}"},
        params: params,
        receive_timeout: 5_000,
        retry: false
      ] ++ Application.get_env(:hermes, :ari_req_options, [])

    result = options |> Req.new() |> Req.request()

    case result do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("ARI #{method} #{path} failed with #{status}")
        {:error, {:http, status, body}}

      {:error, exception} ->
        Logger.warning("ARI #{method} #{path} failed: #{Exception.message(exception)}")
        {:error, {:transport, exception}}
    end
  end
end
