defmodule Valkyrie.Members.SyncScheduler do
  @moduledoc """
  Periodically triggers a member sync from the Authentik API.

  The interval is configurable via:

      config :valkyrie, Valkyrie.Members.SyncScheduler,
        interval_ms: :timer.minutes(15),
        initial_delay_ms: :timer.seconds(30)

  In production, `SYNC_INTERVAL_MINUTES` env var overrides the interval.
  """

  use GenServer
  require Logger

  @default_interval_ms :timer.minutes(15)
  @default_initial_delay_ms :timer.seconds(30)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    interval_ms = get_config(:interval_ms, @default_interval_ms)
    initial_delay_ms = get_config(:initial_delay_ms, @default_initial_delay_ms)

    Logger.info(
      "[SyncScheduler] Starting. Initial sync in #{initial_delay_ms}ms, then every #{interval_ms}ms."
    )

    timer_ref = Process.send_after(self(), :run_sync, initial_delay_ms)
    {:ok, %{interval_ms: interval_ms, timer_ref: timer_ref}}
  end

  @impl true
  def handle_info(:run_sync, %{interval_ms: interval_ms} = state) do
    Logger.info("[SyncScheduler] Triggering periodic member sync.")

    case Valkyrie.Members.update_members_from_xhain_account_system_async() do
      :ok ->
        Logger.info("[SyncScheduler] Sync started successfully.")

      {:error, :already_syncing} ->
        Logger.info("[SyncScheduler] Sync already in progress, skipping.")
    end

    timer_ref = Process.send_after(self(), :run_sync, interval_ms)
    {:noreply, %{state | timer_ref: timer_ref}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{timer_ref: ref}) when not is_nil(ref) do
    Process.cancel_timer(ref)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp get_config(key, default) do
    :valkyrie
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end
end
