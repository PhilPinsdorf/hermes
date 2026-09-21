defmodule Hermes.AriTest do
  use ExUnit.Case, async: false

  alias Hermes.Ari
  alias Hermes.Ari.EventSocket

  setup do
    original = Application.get_env(:hermes, Hermes.Ari)
    on_exit(fn -> Application.put_env(:hermes, Hermes.Ari, original) end)
    :ok
  end

  defp configure(overrides) do
    config = Application.get_env(:hermes, Hermes.Ari, [])
    Application.put_env(:hermes, Hermes.Ari, Keyword.merge(config, overrides))
  end

  describe "enabled?/0" do
    test "needs the flag and a password" do
      configure(enabled: true, password: "secret")
      assert Ari.enabled?()

      configure(enabled: true, password: nil)
      refute Ari.enabled?()

      configure(enabled: false, password: "secret")
      refute Ari.enabled?()
    end
  end

  describe "EventSocket.uri/0" do
    test "builds the websocket URL with app and credentials" do
      configure(
        base_url: "http://127.0.0.1:8088",
        username: "hermes",
        password: "s3cret",
        app: "hermes"
      )

      uri = URI.parse(EventSocket.uri())
      params = URI.decode_query(uri.query)

      assert uri.scheme == "ws"
      assert uri.host == "127.0.0.1"
      assert uri.port == 8088
      assert uri.path == "/ari/events"
      assert params["app"] == "hermes"
      assert params["subscribeAll"] == "true"
      assert params["api_key"] == "hermes:s3cret"
    end

    test "uses wss for https" do
      configure(base_url: "https://asterisk.example:8089", password: "x")
      assert URI.parse(EventSocket.uri()).scheme == "wss"
    end
  end

  describe "status" do
    test "publishes changes only once per transition" do
      Ari.subscribe()
      Ari.put_status(:disconnected)

      Ari.put_status(:connected)
      assert_receive {:ari_status, :connected}
      assert Ari.status() == :connected

      Ari.put_status(:connected)
      refute_receive {:ari_status, :connected}, 50

      Ari.put_status(:disconnected)
      assert_receive {:ari_status, :disconnected}
    end
  end
end
