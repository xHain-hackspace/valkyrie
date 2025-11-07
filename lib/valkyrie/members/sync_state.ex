defmodule Valkyrie.Members.SyncState do
  @moduledoc """
  Agent to track global sync state and prevent concurrent sync operations.
  """
  use Agent

  @name __MODULE__

  def start_link(_opts) do
    Agent.start_link(fn -> nil end, name: @name)
  end

  @doc """
  Returns true if a sync is currently running, false otherwise.
  """
  def is_syncing? do
    Agent.get(@name, fn state -> not is_nil(state) end)
  end

  @doc """
  Attempts to start a sync.
  Returns `:ok` if the lock was acquired, or `{:error, :already_syncing}` if a sync is already running.
  """
  def start_sync do
    Agent.get_and_update(@name, fn
      nil ->
        state = %{started_at: DateTime.utc_now()}
        {:ok, state}

      existing_state ->
        {{:error, :already_syncing}, existing_state}
    end)
  end

  @doc """
  Finishes the current sync, clearing the state.
  """
  def finish_sync do
    Agent.update(@name, fn _state -> nil end)
  end

  @doc """
  Gets the current sync state (for debugging/monitoring).
  """
  def get_state do
    Agent.get(@name, fn state -> state end)
  end
end
