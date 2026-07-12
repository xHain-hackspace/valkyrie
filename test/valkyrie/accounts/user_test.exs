defmodule Valkyrie.Accounts.UserTest do
  use Valkyrie.DataCase, async: false

  alias Valkyrie.Accounts.User

  # config/test.exs sets AUTHENTIK_ADMIN_GROUP=valkyrie-admins
  defp register(user_info) do
    Ash.create!(
      User,
      %{user_info: user_info, oauth_tokens: %{}},
      action: :register_with_xhain_account,
      authorize?: false
    )
  end

  describe "is_admin derivation from the groups claim" do
    test "a user in the configured admin group becomes an admin" do
      user = register(%{"preferred_username" => "alice", "groups" => ["valkyrie-admins", "x"]})
      assert user.is_admin
    end

    test "a user not in the admin group is not an admin" do
      user = register(%{"preferred_username" => "alice", "groups" => ["members"]})
      refute user.is_admin
    end

    test "a missing groups claim is not an admin (fail closed)" do
      user = register(%{"preferred_username" => "alice"})
      refute user.is_admin
    end

    test "re-registering with changed groups refreshes the role (upsert on login)" do
      admin = register(%{"preferred_username" => "alice", "groups" => ["valkyrie-admins"]})
      assert admin.is_admin

      demoted = register(%{"preferred_username" => "alice", "groups" => []})
      refute demoted.is_admin
      assert demoted.id == admin.id
    end
  end
end
