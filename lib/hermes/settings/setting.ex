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
    # Call log retention (phone numbers are personal data).
    field :call_log_retention_days, :integer, default: 90
    field :call_log_anonymize_after_days, :integer
    # Announcement texts; empty means "use the default text".
    field :text_no_one_on_duty, :string
    field :text_all_busy, :string
    field :text_confirm, :string
    field :text_blocked, :string
    field :announce_next_shift, :boolean, default: true
    # Appearance of this installation
    field :brand_name, :string, default: "Hermes"
    field :logo_data, :binary
    field :logo_content_type, :string
    field :logo_updated_at, :utc_datetime
    # Global switch: no forwarding at all while this is off
    field :forwarding_enabled, :boolean, default: true
    field :forwarding_paused_at, :utc_datetime

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
      :busy_policy,
      :call_log_retention_days,
      :call_log_anonymize_after_days,
      :text_no_one_on_duty,
      :text_all_busy,
      :text_confirm,
      :text_blocked,
      :announce_next_shift,
      :brand_name
    ])
    |> update_change(:clip_display_name, &String.trim/1)
    |> validate_required([
      :clip_display_name,
      :ring_timeout_seconds,
      :ring_strategy,
      :max_external_channels,
      :busy_policy,
      :call_log_retention_days
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
    |> validate_number(:call_log_retention_days,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 3650
    )
    |> validate_number(:call_log_anonymize_after_days, greater_than_or_equal_to: 0)
    |> validate_length(:text_no_one_on_duty, max: 500)
    |> validate_length(:text_all_busy, max: 500)
    |> validate_length(:text_confirm, max: 500)
    |> validate_length(:text_blocked, max: 500)
    |> update_change(:brand_name, &String.trim/1)
    |> validate_required([:brand_name])
    |> validate_length(:brand_name, min: 2, max: 40)
    |> validate_anonymize_before_deletion()
  end

  # Anonymizing later than deleting would never happen.
  defp validate_anonymize_before_deletion(changeset) do
    retention = get_field(changeset, :call_log_retention_days)
    anonymize = get_field(changeset, :call_log_anonymize_after_days)

    if retention && anonymize && anonymize >= retention do
      add_error(
        changeset,
        :call_log_anonymize_after_days,
        "muss kleiner als die Aufbewahrungsdauer sein"
      )
    else
      changeset
    end
  end
end
