defmodule HermesWeb.CallLiveTest do
  use HermesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hermes.DirectoryFixtures

  alias Hermes.Calls.Log

  setup :register_and_log_in_user

  defp record(attrs) do
    {:ok, call} =
      attrs
      |> Enum.into(%{
        channel_id: "chan-#{System.unique_integer([:positive])}",
        caller_number: "+4915112345678",
        started_at: DateTime.utc_now() |> DateTime.truncate(:second),
        result: :announced
      })
      |> Log.record()

    call
  end

  test "requires login" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/calls")
  end

  test "shows an empty state", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/calls")
    assert has_element?(lv, "#calls-empty")
  end

  test "lists calls with result, person and attempts", %{conn: conn} do
    anna = person_fixture(name: "Anna")
    bert = person_fixture(name: "Bert")

    record(%{
      result: :bridged,
      person_id: bert.id,
      talk_seconds: 95,
      total_seconds: 130,
      attempts: [
        %{person_id: anna.id, person_name: "Anna", outcome: :no_confirmation},
        %{person_id: bert.id, person_name: "Bert", outcome: :confirmed}
      ]
    })

    {:ok, _lv, html} = live(conn, ~p"/calls")

    assert html =~ "vermittelt"
    assert html =~ "+49 15112345678"
    assert html =~ "Bert"
    assert html =~ "keine Taste"
    assert html =~ "1:35 min"
  end

  test "shows that a number was removed by the retention rules", %{conn: conn} do
    record(%{caller_number: nil})

    {:ok, _lv, html} = live(conn, ~p"/calls")
    assert html =~ "entfernt"
  end

  test "filters by result", %{conn: conn} do
    record(%{result: :bridged, channel_id: "chan-bridged"})
    record(%{result: :announced, channel_id: "chan-announced"})

    {:ok, lv, _html} = live(conn, ~p"/calls")

    html = lv |> form("#call-filter", filter: %{result: "bridged"}) |> render_change()

    assert html =~ "vermittelt"
    refute html =~ "Ansage</span>"
    assert html =~ "1 Anruf"
  end

  test "filters by person and date", %{conn: conn} do
    anna = person_fixture(name: "Anna")
    record(%{result: :bridged, person_id: anna.id, started_at: ~U[2026-09-10 10:00:00Z]})
    record(%{result: :announced, started_at: ~U[2026-09-20 10:00:00Z]})

    {:ok, lv, _html} = live(conn, ~p"/calls")

    html = lv |> form("#call-filter", filter: %{person_id: anna.id}) |> render_change()
    assert html =~ "1 Anruf"

    html =
      lv |> form("#call-filter", filter: %{person_id: "", from: "2026-09-15"}) |> render_change()

    assert html =~ "1 Anruf"
    assert html =~ "Ansage"
  end

  test "a new call appears without reloading", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/calls")
    assert has_element?(lv, "#calls-empty")

    record(%{caller_number: "+4930111222"})

    refute has_element?(lv, "#calls-empty")
    assert render(lv) =~ "+49 30111222"
  end
end
