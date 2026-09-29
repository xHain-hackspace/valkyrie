defmodule Valkyrie.Accounts.UserTest do
  use Valkyrie.DataCase, async: false

  alias Valkyrie.Accounts.User
  alias Valkyrie.Accounts.UserIdentity

  require Ash.Query

  # config/test.exs sets AUTHENTIK_ADMIN_GROUP=valkyrie-admins
  defp register(user_info) do
    {:ok, user} = try_register(user_info)
    user
  end

  defp try_register(user_info) do
    Ash.create(
      User,
      %{user_info: Map.put_new(user_info, "sub", "sub-alice"), oauth_tokens: %{}},
      action: :register_with_xhain_account,
      authorize?: false
    )
  end

  # A user as created before identities were stored: no identity row.
  defp legacy_user(username) do
    Ash.Seed.seed!(User, %{username: username})
  end

  defp identity_uids(user) do
    UserIdentity
    |> Ash.Query.filter(user_id == ^user.id)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.uid)
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

  describe "identities" do
    test "registering stores the provider identity" do
      user = register(%{"preferred_username" => "alice"})
      assert identity_uids(user) == ["sub-alice"]
    end

    test "a pre-existing user without identity is linked on first sign-in" do
      legacy = legacy_user("alice")

      user = register(%{"preferred_username" => "alice", "groups" => ["valkyrie-admins"]})

      assert user.id == legacy.id
      assert user.is_admin
      assert identity_uids(legacy) == ["sub-alice"]
    end

    test "a known sub keeps signing in to its user" do
      first = register(%{"preferred_username" => "alice"})
      again = register(%{"preferred_username" => "alice"})
      assert again.id == first.id
    end

    test "a different sub for an already linked username is rejected" do
      register(%{"preferred_username" => "alice"})

      assert {:error, _} = try_register(%{"preferred_username" => "alice", "sub" => "other"})
    end

    test "a sign-in without sub is rejected" do
      assert {:error, _} =
               Ash.create(
                 User,
                 %{user_info: %{"preferred_username" => "alice"}, oauth_tokens: %{}},
                 action: :register_with_xhain_account,
                 authorize?: false
               )
    end
  end
end
