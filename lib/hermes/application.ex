defmodule Hermes.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      HermesWeb.Telemetry,
      Hermes.Repo,
      {DNSCluster, query: Application.get_env(:hermes, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Hermes.PubSub},
      # Background work that must not block a request or a call
      {Task.Supervisor, name: Hermes.TaskSupervisor},
      # One process per call, registered under its channel id
      {Registry, keys: :unique, name: Hermes.Calls.Registry},
      # Who and which line channel is busy right now
      Hermes.Calls.Occupancy,
      Hermes.Calls.CallSupervisor,
      # Deletes old call log entries once a day
      Hermes.Calls.Retention,
      # Connects to Asterisk; :ignore without credentials (tests, dev)
      Hermes.Ari.EventSocket,
      # Start to serve requests, typically the last entry
      HermesWeb.Endpoint
    ]

    install_sounds()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hermes.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      refresh_sounds()
      {:ok, pid}
    end
  end

  # Announcements live in a volume shared with Asterisk; a missing volume must
  # not keep the web UI from starting.
  defp install_sounds do
    case Hermes.Sounds.install_defaults() do
      {:ok, []} -> :ok
      {:ok, copied} -> Logger.info("installed announcements: #{inspect(copied)}")
      {:error, reason} -> Logger.warning("sounds directory unavailable: #{inspect(reason)}")
    end
  end

  # Regenerate announcements whose text changed while Hermes was down.
  defp refresh_sounds do
    Hermes.Sounds.refresh_async()
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HermesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
