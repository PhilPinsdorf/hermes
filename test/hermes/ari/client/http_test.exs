defmodule Hermes.Ari.Client.HttpTest do
  use ExUnit.Case, async: false

  alias Hermes.Ari.Client.Http

  # Answers ARI requests in-process instead of over the network.
  defp with_asterisk(fun) when is_function(fun, 1) do
    test_pid = self()

    plug = fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      send(test_pid, {:request, conn.method, conn.request_path, conn.query_params})
      fun.(conn)
    end

    Application.put_env(:hermes, :ari_req_options, plug: plug)
    on_exit(fn -> Application.delete_env(:hermes, :ari_req_options) end)
  end

  defp respond(conn, status, body \\ %{}) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, Jason.encode!(body))
  end

  test "answer/1 posts to the channel" do
    with_asterisk(&respond(&1, 204))

    assert Http.answer("chan-1") == :ok
    assert_receive {:request, "POST", "/ari/channels/chan-1/answer", _}
  end

  test "play/2 passes the media URI and returns the playback id" do
    with_asterisk(&respond(&1, 201, %{"id" => "pb-42"}))

    assert Http.play("chan-1", "sound:/tmp/hello") == {:ok, "pb-42"}
    assert_receive {:request, "POST", "/ari/channels/chan-1/play", params}
    assert params["media"] == "sound:/tmp/hello"
    assert is_binary(params["playbackId"])
  end

  test "hangup/1 deletes the channel" do
    with_asterisk(&respond(&1, 204))

    assert Http.hangup("chan-1") == :ok
    assert_receive {:request, "DELETE", "/ari/channels/chan-1", _}
  end

  test "hangup/1 treats an already gone channel as success" do
    with_asterisk(&respond(&1, 404, %{"message" => "Channel not found"}))

    assert Http.hangup("chan-1") == :ok
  end

  test "errors are returned, not raised" do
    with_asterisk(&respond(&1, 500, %{"message" => "boom"}))

    assert {:error, {:http, 500, _}} = Http.answer("chan-1")
    assert {:error, {:http, 500, _}} = Http.play("chan-1", "sound:x")
  end

  test "a transport failure is returned as well" do
    # Nothing listens on port 1: connection refused.
    config = Application.get_env(:hermes, Hermes.Ari, [])
    Application.put_env(:hermes, Hermes.Ari, Keyword.put(config, :base_url, "http://127.0.0.1:1"))
    on_exit(fn -> Application.put_env(:hermes, Hermes.Ari, config) end)

    assert {:error, {:transport, _}} = Http.answer("chan-1")
  end

  test "asterisk_info/0 returns the decoded body" do
    with_asterisk(&respond(&1, 200, %{"system" => %{"version" => "22.11.0"}}))

    assert {:ok, %{"system" => %{"version" => "22.11.0"}}} = Http.asterisk_info()
  end

  test "requests are authenticated" do
    with_asterisk(fn conn ->
      assert ["Basic " <> _] = Plug.Conn.get_req_header(conn, "authorization")
      respond(conn, 204)
    end)

    assert Http.answer("chan-1") == :ok
  end
end
