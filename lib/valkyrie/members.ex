defmodule Valkyrie.Members do
  use Ash.Domain, otp_app: :valkyrie, extensions: [AshAdmin.Domain]

  require Logger

  alias Valkyrie.Authentik
  alias Valkyrie.Members.Member

  @member_group_uuid "005b0c1c-c1bf-4a57-99b2-66cf04f94cda"

  admin do
    show? true
  end

  resources do
    resource Valkyrie.Members.Member do
      define :change_keyholder_status, action: :change_keyholder_status
      define :list_members, action: :read
      define :create_member, action: :create
      define :create_manual_entry, action: :create_manual_entry
      define :delete_member, action: :destroy
      define :update_manual_entry, action: :update_manual_entry
    end
  end

  def get_member_by_username(username) do
    Ash.get(Valkyrie.Members.Member, %{username: username})
  end

  def update_members_from_xhain_account_system do
    case Authentik.get_all_users() do
      {:ok, users} ->
        {:ok,
         users
         |> Enum.filter(&has_required_attributes?/1)
         |> Enum.map(&xhain_account_to_member_info/1)
         |> Enum.each(fn member ->
           IO.inspect(member, label: "######## member before create")
           Ash.create!(Member, member, action: :create)
         end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp xhain_account_to_member_info(%Authentik.XHainAccount{} = xhain_account) do
    %{
      username: xhain_account.username,
      xhain_account_id: xhain_account.xhain_account_id,
      ssh_public_key: xhain_account.ssh_public_key,
      tree_name: xhain_account.tree_name,
      is_active: is_member_in_group(xhain_account.groups, @member_group_uuid),
      has_key: get_key_status(xhain_account)
    }
  end

  defp has_required_attributes?(xhain_account) do
    has_username = xhain_account.username != nil and xhain_account.username != ""
    has_xhain_account_id = xhain_account.xhain_account_id != nil
    has_tree_name = xhain_account.tree_name != nil and xhain_account.tree_name != ""

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

  defp get_key_status(member) do
    case get_member_by_username(member.username) do
      {:ok, member} ->
        member.has_key

      _ ->
        false
    end
  end
end
