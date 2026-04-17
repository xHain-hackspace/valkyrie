defmodule Valkyrie.Members.SyncStateTest do
  use ExUnit.Case, async: false

  alias Valkyrie.Members.SyncState

  setup do
    SyncState.finish_sync()
    :ok
  end

  test "is_syncing? returns false when no sync is running" do
    refute SyncState.is_syncing?()
  end

  test "start_sync/0 acquires the lock and returns :ok" do
    assert :ok = SyncState.start_sync()
    assert SyncState.is_syncing?()
  end

  test "start_sync/0 returns already_syncing error when lock is held" do
    :ok = SyncState.start_sync()
    assert {:error, :already_syncing} = SyncState.start_sync()
  end

  test "finish_sync/0 releases the lock" do
    :ok = SyncState.start_sync()
    SyncState.finish_sync()
    refute SyncState.is_syncing?()
  end
end
