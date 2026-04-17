defmodule Valkyrie.MemberHelpers do
  alias Valkyrie.Members.Member

  @valid_ssh_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOn6J0bzZLnNNvMVDzyP63RNQjdT3BgBRZLm2wO+9sZl"

  def member_fixture(attrs \\ %{}) do
    defaults = %{
      username: "testuser",
      xhain_account_id: 1,
      tree_name: "birke",
      ssh_public_key: @valid_ssh_key,
      is_active: true,
      has_key: true
    }

    Ash.create!(Member, Map.merge(defaults, attrs), action: :create)
  end

  def valid_ssh_key, do: @valid_ssh_key
end
