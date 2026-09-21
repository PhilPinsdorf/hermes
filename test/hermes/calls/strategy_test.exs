defmodule Hermes.Calls.StrategyTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Hermes.Calls.Strategy

  test "sequential always dials one leg" do
    assert Strategy.legs_to_dial(:sequential, 1, 3) == 1
    assert Strategy.legs_to_dial(:sequential, 5, 3) == 1
  end

  test "simultaneous dials as many legs as channels and people allow" do
    assert Strategy.legs_to_dial(:simultaneous, 5, 3) == 3
    assert Strategy.legs_to_dial(:simultaneous, 2, 7) == 2
  end

  test "simultaneous degrades to one leg on a two-channel line, with a warning" do
    log = capture_log(fn -> assert Strategy.legs_to_dial(:simultaneous, 1, 4) == 1 end)
    assert log =~ "degraded to :sequential"
  end

  test "nothing is dialed without free channels or people" do
    assert Strategy.legs_to_dial(:simultaneous, 0, 4) == 0
    assert Strategy.legs_to_dial(:sequential, 0, 4) == 0
    assert Strategy.legs_to_dial(:sequential, 3, 0) == 0
  end
end
