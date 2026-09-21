defmodule Hermes.Telephony.Monitor do
  @moduledoc """
  Watches the parts a call depends on and raises the alarm when one of them
  is gone — silently broken telephony is the worst failure mode of all:
  nobody notices until a caller complains.

  Checked every `interval`:

    * the ARI connection (does Hermes reach Asterisk?)
    * the trunk endpoint (does Asterisk reach the Fritz!Box?)

  The result is published as `{:telephony_status, status}` and shown in the
  web UI; a change to "not ready" is logged as an error, so it also shows up
  in `docker compose logs`.
  """
  use GenServer

  require Logger

  alias Hermes.Ari

  @interval :timer.seconds(30)
  @topic "telephony"

  defstruct [:interval, status: :unknown, trunk: :unknown, since: nil]

  def start_link(opts) do
    # Tests start their own monitor next to the application's one.
    case Keyword.pop(opts, :name, __MODULE__) do
      {nil, opts} -> GenServer.start_link(__MODULE__, opts)
      {name, opts} -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc "Subscribes to `{:telephony_status, status}` messages."
  def subscribe, do: Phoenix.PubSub.subscribe(Hermes.PubSub, @topic)

  @doc """
  Current state:

      %{ready?: boolean, ari: :connected | :disconnected,
        trunk: :online | :offline | :unknown, since: DateTime.t() | nil}
  """
  def status do
    case Process.whereis(__MODULE__) do
      nil -> %{ready?: false, ari: Ari.status(), trunk: :unknown, since: nil}
      _pid -> GenServer.call(__MODULE__, :status)
    end
  end

  @doc "Checks right now instead of waiting for the next round."
  def check_now, do: GenServer.call(__MODULE__, :check, 15_000)

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @interval)
    if Keyword.get(opts, :check_on_start, true), do: Process.send_after(self(), :check, 5_000)
    {:ok, %__MODULE__{interval: interval}}
  end

  @impl true
  def handle_info(:check, state) do
    state = check(state)
    Process.send_after(self(), :check, state.interval)
    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, to_status(state), state}

  def handle_call(:check, _from, state) do
    state = check(state)
    {:reply, to_status(state), state}
  end

  defp check(state) do
    ari = Ari.status()
    trunk = if ari == :connected, do: trunk_state(), else: :unknown
    ready? = ari == :connected and trunk == :online
    previous = state.status
    status = if ready?, do: :ready, else: :not_ready

    state = %{state | status: status, trunk: trunk}

    cond do
      previous == status ->
        state

      status == :not_ready ->
        Logger.error(
          "telephony not ready: ARI #{ari}, trunk #{trunk} – incoming calls may not be handled"
        )

        announce(%{state | since: DateTime.utc_now()})

      true ->
        Logger.info("telephony ready again")
        announce(%{state | since: DateTime.utc_now()})
    end
  end

  # Asterisk reports an endpoint as "online" while the Fritz!Box answers the
  # regular OPTIONS checks (qualify).
  defp trunk_state do
    case Ari.endpoint(trunk_endpoint()) do
      {:ok, %{"state" => "online"}} -> :online
      {:ok, %{"state" => _other}} -> :offline
      {:error, _reason} -> :offline
    end
  end

  defp trunk_endpoint, do: Application.get_env(:hermes, :trunk_endpoint, "PJSIP/fritzbox")

  defp announce(state) do
    Phoenix.PubSub.broadcast(Hermes.PubSub, @topic, {:telephony_status, to_status(state)})
    state
  end

  defp to_status(state) do
    %{
      ready?: state.status == :ready,
      ari: Ari.status(),
      trunk: state.trunk,
      since: state.since
    }
  end
end
