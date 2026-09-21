defmodule Hermes.Calls.Strategy do
  @moduledoc """
  How many mobile phones may ring at the same time.

  The honest limit is the line, not the setting: every leg costs one channel,
  and the incoming call already holds one. On a Fritz!Box with two channels
  exactly one channel is left, so `:simultaneous` quietly becomes
  `:sequential` — with a SIP trunk (4–8 channels) it really rings in parallel.
  """

  require Logger

  @doc """
  Number of legs to dial in this round.

  * `strategy` — `:sequential` or `:simultaneous`
  * `free_channels` — channels still free on the line
  * `waiting` — how many people are left to try
  """
  @spec legs_to_dial(:sequential | :simultaneous, non_neg_integer(), non_neg_integer()) ::
          non_neg_integer()
  def legs_to_dial(_strategy, free_channels, waiting) when free_channels <= 0 or waiting <= 0,
    do: 0

  def legs_to_dial(:sequential, _free_channels, _waiting), do: 1

  def legs_to_dial(:simultaneous, free_channels, waiting) do
    case min(free_channels, waiting) do
      1 ->
        Logger.warning(
          "ring strategy :simultaneous degraded to :sequential – only one free channel " <>
            "(a Fritz!Box line allows two calls, one of them is the caller)"
        )

        1

      legs ->
        legs
    end
  end
end
