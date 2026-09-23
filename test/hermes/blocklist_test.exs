defmodule Hermes.BlocklistTest do
  use Hermes.DataCase, async: true

  alias Hermes.Blocklist

  describe "block/1" do
    test "stores the number in E.164, however it was typed" do
      assert {:ok, entry} = Blocklist.block(%{number: "0171 1234567"})
      assert entry.number == "+491711234567"
    end

    test "keeps an optional note" do
      assert {:ok, entry} = Blocklist.block(%{number: "0171 1234567", note: " Werbung "})
      assert entry.note == "Werbung"
    end

    test "refuses the same number twice, whatever notation" do
      assert {:ok, _} = Blocklist.block(%{number: "0171 1234567"})
      assert {:error, changeset} = Blocklist.block(%{number: "+49 171 1234567"})
      assert "ist bereits blockiert" in errors_on(changeset).number
    end

    test "refuses what is not a number" do
      assert {:error, changeset} = Blocklist.block(%{number: "1234567"})
      assert changeset.errors[:number]
    end
  end

  describe "blocked?/2" do
    setup do
      {:ok, _} = Blocklist.block(%{number: "+491711234567"})
      :ok
    end

    test "recognises the number in any notation" do
      # Asterisk hands the caller over the way the Fritz!Box says it, which is
      # national — the blocklist stores E.164.
      assert Blocklist.blocked?("01711234567")
      assert Blocklist.blocked?("+491711234567")
      assert Blocklist.blocked?("+49 171 1234567")
    end

    test "lets everything else through" do
      refute Blocklist.blocked?("+491719999999")
      refute Blocklist.blocked?(nil)
      refute Blocklist.blocked?("")
      refute Blocklist.blocked?("unbekannt")
    end

    test "takes a prepared set, so a whole call list needs one query" do
      numbers = Blocklist.numbers()

      assert Blocklist.blocked?("01711234567", numbers)
      refute Blocklist.blocked?("01719999999", numbers)
    end
  end

  test "unblock/1 lets the number through again" do
    {:ok, entry} = Blocklist.block(%{number: "+491711234567"})
    assert Blocklist.blocked?("+491711234567")

    {:ok, _} = Blocklist.unblock(entry)

    refute Blocklist.blocked?("+491711234567")
    assert Blocklist.list() == []
  end
end
