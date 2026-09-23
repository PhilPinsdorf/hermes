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

    assert html =~ "Vermittelt"
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

    assert html =~ "Vermittelt"
    refute html =~ "Ansage</span>"
    assert html =~ "1 Anruf"
  end

  test "opens on the last month", %{conn: conn} do
    today = DateTime.utc_now() |> Hermes.Schedule.local_naive() |> NaiveDateTime.to_date()
    record(%{caller_number: "+4930111222"})
    record(%{caller_number: "+4930999888", started_at: two_months_ago()})

    {:ok, lv, html} = live(conn, ~p"/calls")

    # The dates are pre-filled and the older call is outside the window.
    assert has_element?(lv, ~s(#call-filter input[name="filter[to]"][value="#{today}"]))
    assert html =~ "1 Anruf"
    assert html =~ "+49 30111222"
    refute html =~ "+49 30999888"

    # Clearing the window brings it back.
    html = lv |> form("#call-filter", filter: %{from: "", to: ""}) |> render_change()
    assert html =~ "2 Anrufe"
  end

  defp two_months_ago do
    DateTime.utc_now() |> DateTime.add(-62, :day) |> DateTime.truncate(:second)
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

  test "searches for a number, however it is typed", %{conn: conn} do
    record(%{caller_number: "+491711234567"})
    record(%{caller_number: "+4930999888"})

    {:ok, lv, _html} = live(conn, ~p"/calls")

    for typed <- ["0171 1234567", "+49 171", "1711234"] do
      html = lv |> form("#call-filter", filter: %{number: typed}) |> render_change()

      assert html =~ "1 Anruf"
      assert html =~ "+49 1711234567"
      refute html =~ "+49 30999888"
    end

    html = lv |> form("#call-filter", filter: %{number: ""}) |> render_change()
    assert html =~ "2 Anrufe"
  end

  test "filters by everyone who was rung, not just by who took the call", %{conn: conn} do
    anna = person_fixture(name: "Anna")
    bert = person_fixture(name: "Bert")

    # Anna's phone rang first, Bert ended up taking the call.
    record(%{
      caller_number: "+4930111222",
      result: :bridged,
      person_id: bert.id,
      attempts: [
        %{person_id: anna.id, person_name: "Anna", outcome: :no_answer},
        %{person_id: bert.id, person_name: "Bert", outcome: :confirmed}
      ]
    })

    record(%{caller_number: "+4930999888", result: :announced})

    {:ok, lv, _html} = live(conn, ~p"/calls")

    html = lv |> form("#call-filter", filter: %{attendee_id: anna.id}) |> render_change()
    assert html =~ "1 Anruf"
    assert html =~ "+49 30111222"

    # The same call, asked for the other way round: Anna never took it.
    html =
      lv
      |> form("#call-filter", filter: %{attendee_id: "", person_id: anna.id})
      |> render_change()

    assert html =~ "0 Anrufe"
    assert has_element?(lv, "#calls-empty")
  end

  describe "blocking from the list" do
    test "offers the button and blocks the caller", %{conn: conn} do
      call = record(%{caller_number: "+4930111222"})

      {:ok, lv, _html} = live(conn, ~p"/calls")

      assert has_element?(lv, "#block-#{call.id}", "Blockieren")

      # The button asks first, in a dialog of our own — no browser box.
      lv |> element("#block-#{call.id}") |> render_click()
      assert has_element?(lv, "#confirm-block", "+49 30111222")

      lv |> element("#confirm-block-confirm") |> render_click()

      assert [%{number: "+4930111222", note: "Aus der Anrufliste blockiert"}] =
               Hermes.Blocklist.list()

      refute has_element?(lv, "#confirm-block")
    end

    test "cancelling the dialog blocks nothing", %{conn: conn} do
      call = record(%{caller_number: "+4930111222"})
      {:ok, lv, _html} = live(conn, ~p"/calls")

      lv |> element("#block-#{call.id}") |> render_click()
      lv |> element("#confirm-block-cancel") |> render_click()

      refute has_element?(lv, "#confirm-block")
      assert Hermes.Blocklist.list() == []
      assert has_element?(lv, "#block-#{call.id}")
    end

    test "every row of that caller greys out, not just the one clicked", %{conn: conn} do
      # The same caller three times, plus somebody else who must stay clickable.
      same = for _ <- 1..3, do: record(%{caller_number: "+4930111222"})
      other = record(%{caller_number: "+4930999888"})

      {:ok, lv, _html} = live(conn, ~p"/calls")
      assert offered(lv) == 4

      lv |> element("#block-#{hd(same).id}") |> render_click()
      lv |> element("#confirm-block-confirm") |> render_click()

      for call <- same do
        assert has_element?(lv, "#blocked-#{call.id}", "Blockiert")
        refute has_element?(lv, "#block-#{call.id}")
      end

      assert has_element?(lv, "#block-#{other.id}", "Blockieren")
      assert offered(lv) == 1
    end

    test "a number blocked elsewhere greys the rows out too", %{conn: conn} do
      call = record(%{caller_number: "+4930111222"})
      {:ok, lv, _html} = live(conn, ~p"/calls")

      # Blocked on the blocklist page, in another session.
      {:ok, _} = Hermes.Blocklist.block(%{number: "+4930111222"})

      assert has_element?(lv, "#blocked-#{call.id}", "Blockiert")
      assert offered(lv) == 0
    end

    test "an anonymized entry offers nothing to block", %{conn: conn} do
      record(%{caller_number: nil})

      {:ok, lv, _html} = live(conn, ~p"/calls")

      assert offered(lv) == 0
      refute render(lv) =~ ~s(id="blocked-)
    end
  end

  # How many rows still offer blocking. Counted by id, because the word
  # "Blockiert" also appears in the navigation.
  defp offered(lv) do
    lv |> render() |> then(&Regex.scan(~r/id="block-[0-9]+"/, &1)) |> length()
  end

  test "a new call appears without reloading", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/calls")
    assert has_element?(lv, "#calls-empty")

    record(%{caller_number: "+4930111222"})

    refute has_element?(lv, "#calls-empty")
    assert render(lv) =~ "+49 30111222"
  end

  test "table cells carry their column name, so phones can stack them", %{conn: conn} do
    record(%{result: :bridged})

    {:ok, _lv, html} = live(conn, ~p"/calls")

    assert html =~ ~s(data-label="Zeitpunkt")
    assert html =~ ~s(data-label="Ergebnis")
    assert html =~ "table-cards"
  end
end
