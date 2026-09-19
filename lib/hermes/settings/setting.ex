defmodule Hermes.Settings.Setting do
  @moduledoc """
  The single row of global settings (`id` is always 1, enforced by a check
  constraint).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Hermes.Directory.PhoneNumber

  @ring_strategies [:sequential, :simultaneous]
  @busy_policies [:announce]

  schema "settings" do
    # The number every forwarded call shows on the handset (the landline).
    field :clip_number, :string
    # The one name everyone stores for `clip_number` in their address book.
    field :clip_display_name, :string, default: "Bereitschaft"
    field :ring_timeout_seconds, :integer, default: 25
    field :ring_strategy, Ecto.Enum, values: @ring_strategies, default: :sequential
    # Concurrent external calls the line allows; incoming and outgoing legs both count.
    field :max_external_channels, :integer, default: 2
    field :busy_policy, Ecto.Enum, values: @busy_policies, default: :announce

    timestamps(type: :utc_datetime)
  end

  def ring_strategies, do: @ring_strategies
  def busy_policies, do: @busy_policies

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [
      :clip_number,
      :clip_display_name,
      :ring_timeout_seconds,
      :ring_strategy,
      :max_external_channels,
      :busy_policy
    ])
    |> update_change(:clip_display_name, &String.trim/1)
    |> validate_required([
      :clip_display_name,
      :ring_timeout_seconds,
      :ring_strategy,
      :max_external_channels,
      :busy_policy
    ])
    |> validate_length(:clip_display_name, max: 60)
    |> PhoneNumber.validate_change(:clip_number)
    |> validate_number(:ring_timeout_seconds,
      greater_than_or_equal_to: 5,
      less_than_or_equal_to: 120
    )
    |> validate_number(:max_external_channels,
      greater_than_or_equal_to: 2,
      less_than_or_equal_to: 30
    )
  end
end
