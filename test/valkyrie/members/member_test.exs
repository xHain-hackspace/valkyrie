defmodule Valkyrie.Members.MemberTest do
  use Valkyrie.DataCase, async: false

  alias Valkyrie.Members.Member
  alias Valkyrie.Members.KeyTargets

  setup do
    ensure_key_targets()
    :ok
  end

  defp target_id(slug), do: Enum.find(KeyTargets.all(), &(&1.slug == slug)).id

  defp target_slugs(member) do
    member |> Ash.load!(:key_targets) |> Map.fetch!(:key_targets) |> Enum.map(& &1.slug)
  end

  describe "ssh_public_key_valid?/1" do
    test "nil returns false" do
      refute Member.ssh_public_key_valid?(nil)
    end

    test "empty string returns false" do
      refute Member.ssh_public_key_valid?("")
    end

    test "garbage string returns false" do
      refute Member.ssh_public_key_valid?("not-a-valid-key")
    end

    test "valid ed25519 key returns true" do
      assert Member.ssh_public_key_valid?(valid_ssh_key())
    end
  end

  describe ":create_manual_entry action" do
    test "sets is_manual_entry to true and is_active to true" do
      member =
        Ash.create!(Member, %{username: "alice", tree_name: "aloe", key_target_ids: []},
          action: :create_manual_entry
        )

      assert member.is_manual_entry == true
      assert member.is_active == true
    end

    test "grants the given key targets" do
      member =
        Ash.create!(
          Member,
          %{username: "alice", tree_name: "aloe", key_target_ids: [target_id("g16")]},
          action: :create_manual_entry
        )

      assert target_slugs(member) == ["g16"]
    end

    test "defaults xhain_account_id to -1" do
      member =
        Ash.create!(Member, %{username: "alice", tree_name: "aloe"}, action: :create_manual_entry)

      assert member.xhain_account_id == -1
    end

    test "creates a new member when a same-username member is archived" do
      member = member_fixture(%{username: "alice"})
      Ash.destroy!(member)

      new_member =
        Ash.create!(Member, %{username: "alice", tree_name: "aloe"}, action: :create_manual_entry)

      assert new_member.username == "alice"
      assert is_nil(new_member.archived_at)
    end
  end

  describe ":update_manual_entry action" do
    test "can update username, tree_name, ssh_public_key and key targets" do
      member =
        Ash.create!(Member, %{username: "alice", tree_name: "aloe", key_target_ids: []},
          action: :create_manual_entry
        )

      updated =
        Ash.update!(
          member,
          %{username: "alice2", tree_name: "birke", key_target_ids: [target_id("g16")]},
          action: :update_manual_entry
        )

      assert updated.username == "alice2"
      assert updated.tree_name == "birke"
      assert target_slugs(updated) == ["g16"]
    end

    test "rejects unknown key targets" do
      member =
        Ash.create!(Member, %{username: "alice", tree_name: "aloe", key_target_ids: []},
          action: :create_manual_entry
        )

      assert {:error, _} =
               Ash.update(member, %{key_target_ids: [Ecto.UUID.generate()]},
                 action: :update_manual_entry
               )
    end
  end

  describe ":change_keyholder_status action" do
    test "updates the set of granted key targets" do
      member = member_fixture(%{key_targets: []})

      with_key =
        Ash.update!(member, %{key_target_ids: [target_id("g16")]},
          action: :change_keyholder_status
        )

      assert target_slugs(with_key) == ["g16"]

      without_key =
        Ash.update!(with_key, %{key_target_ids: []}, action: :change_keyholder_status)

      assert target_slugs(without_key) == []
    end

    test "rejects unknown key targets" do
      member = member_fixture(%{key_targets: []})

      assert {:error, _} =
               Ash.update(member, %{key_target_ids: [Ecto.UUID.generate()]},
                 action: :change_keyholder_status
               )
    end
  end

  describe "soft delete / archival" do
    test "destroyed member is excluded from default read" do
      member = member_fixture()
      Ash.destroy!(member)

      members = Ash.read!(Member)
      assert Enum.empty?(members)
    end

    test "destroyed member is included in read_for_audit_log" do
      member = member_fixture()
      Ash.destroy!(member)

      members = Ash.read!(Member, action: :read_for_audit_log)
      assert Enum.any?(members, &(&1.id == member.id))
    end

    test "archived username can be reused by a new member" do
      member = member_fixture(%{username: "alice"})
      Ash.destroy!(member)

      new_member =
        Ash.create!(Member, %{username: "alice", tree_name: "aloe"}, action: :create_manual_entry)

      assert new_member.username == "alice"
      assert is_nil(new_member.archived_at)

      active_members = Ash.read!(Member)
      assert length(active_members) == 1
    end
  end
end
