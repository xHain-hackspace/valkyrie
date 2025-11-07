defmodule Valkyrie.Members do
  use Ash.Domain, otp_app: :valkyrie, extensions: [AshAdmin.Domain, AshPaperTrail.Domain]

  require Logger
  require Ash.Query

  alias Valkyrie.Authentik
  alias Valkyrie.Members.Member
  alias Valkyrie.Members.SyncState

  @member_group_uuid "005b0c1c-c1bf-4a57-99b2-66cf04f94cda"
  @sync_progress_topic "sync_members:progress"

  admin do
    show? true
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Valkyrie.Members.Member.Version do
      define :list_versions, action: :read, default_options: [load: [:user, :version_source]]
    end

    resource Valkyrie.Members.Member do
      define :change_keyholder_status, action: :change_keyholder_status
      define :list_members, action: :read
      define :create_member, action: :create
      define :create_manual_entry, action: :create_manual_entry
      define :delete_member, action: :destroy
      define :update_manual_entry, action: :update_manual_entry
    end

    resource Valkyrie.Members.LastAccess do
      define :access, action: :access
    end
  end

  def get_member_by_username(username) do
    Ash.get(Valkyrie.Members.Member, %{username: username})
  end

  def update_members_from_xhain_account_system do
    perform_sync()
  end

  def update_members_from_xhain_account_system_async() do
    case SyncState.start_sync() do
      :ok ->
        task = Task.async(fn -> perform_sync() end)
        {:ok, task}

      {:error, :already_syncing} ->
        {:error, :already_syncing}
    end
  end

  defp perform_sync() do
    try do
      progress_callback = create_progress_callback()

      case Authentik.get_all_users(progress_callback) do
        {:ok, users} ->
          valid_users = process_valid_users(users)
          broadcast_progress(:processing, length(valid_users))
          remove_obsolete_members(valid_users)
          create_members(valid_users)
          broadcast_progress(:completed, length(valid_users))

        {:error, reason} ->
          handle_sync_error(reason)
      end
    rescue
      e ->
        handle_sync_error(Exception.message(e))
        raise e
    after
      SyncState.finish_sync()
    end
  end

  defp create_progress_callback() do
    fn progress ->
      Phoenix.PubSub.broadcast(
        Valkyrie.PubSub,
        @sync_progress_topic,
        {:sync_progress, progress}
      )
    end
  end

  defp process_valid_users(users) do
    users
    |> Enum.filter(&has_required_attributes?/1)
    |> Enum.map(&xhain_account_to_member_info/1)
  end

  defp remove_obsolete_members(valid_users) do
    Member
    |> Ash.Query.filter(is_manual_entry: false)
    |> Ash.read!()
    |> Enum.filter(fn member -> not member_exists_in_list?(member, valid_users) end)
    |> Enum.each(fn member ->
      Logger.info("Removing member #{inspect(member)}")
      Ash.destroy!(member, action: :destroy)
    end)
  end

  defp create_members(valid_users) do
    Enum.each(valid_users, fn member ->
      Ash.create!(Member, member, action: :create)
    end)
  end

  defp broadcast_progress(status, users_count) do
    progress_data = %{
      page: nil,
      total_pages: nil,
      users_fetched: users_count,
      status: status
    }

    Phoenix.PubSub.broadcast(
      Valkyrie.PubSub,
      @sync_progress_topic,
      {:sync_progress, progress_data}
    )
  end

  defp handle_sync_error(reason) do
    progress_data = %{
      page: nil,
      total_pages: nil,
      users_fetched: 0,
      status: :error,
      error: reason
    }

    Phoenix.PubSub.broadcast(
      Valkyrie.PubSub,
      @sync_progress_topic,
      {:sync_progress, progress_data}
    )
  end

  ## Helper functions ##

  defp xhain_account_to_member_info(%Authentik.XHainAccount{} = xhain_account) do
    %{
      username: xhain_account.username,
      xhain_account_id: xhain_account.xhain_account_id,
      ssh_public_key: xhain_account.ssh_public_key,
      tree_name: xhain_account.tree_name,
      is_active: is_member_in_group(xhain_account.groups, @member_group_uuid)
    }
  end

  defp member_exists_in_list?(member, valid_users) do
    Enum.any?(valid_users, fn valid_user -> is_same_user?(member, valid_user) end)
  end

  defp is_same_user?(user1, user2) do
    user1.username == user2.username
  end

  defp has_required_attributes?(xhain_account) do
    has_username = not is_nil(xhain_account.username) and xhain_account.username != ""
    has_xhain_account_id = not is_nil(xhain_account.xhain_account_id)
    has_tree_name = not is_nil(xhain_account.tree_name) and xhain_account.tree_name != ""

    if not has_username or not has_xhain_account_id or not has_tree_name do
      Logger.warning(
        "Skipping user #{inspect(xhain_account)} because some attributes are missing"
      )

      false
    else
      true
    end
  end

  defp is_member_in_group(groups, group_uuid) do
    Enum.any?(groups, fn group -> group == group_uuid end)
  end
end
