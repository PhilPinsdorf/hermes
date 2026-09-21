defmodule Hermes.Telephony do
  @moduledoc """
  Access to the configured trunk (`Hermes.Telephony.Trunk`).
  """

  @behaviour Hermes.Telephony.Trunk

  @doc "The trunk implementation in use."
  def trunk, do: Application.get_env(:hermes, :trunk, Hermes.Telephony.Trunk.FritzBox)

  @impl true
  def endpoint_for(number), do: trunk().endpoint_for(number)

  @impl true
  def caller_id, do: trunk().caller_id()

  @impl true
  def max_concurrent_legs, do: trunk().max_concurrent_legs()
end
