defmodule Valkyrie.Members.MemberTest do
  use Valkyrie.DataCase, async: false

  alias Valkyrie.Members.Member

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
        Ash.create!(Member, %{username: "alice", tree_name: "aloe", key_targets: []},
          action: :create_manual_entry
        )

      assert member.is_manual_entry == true
      assert member.is_active == true
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
    test "can update username, tree_name, ssh_public_key and key_targets" do
      member =
        Ash.create!(Member, %{username: "alice", tree_name: "aloe", key_targets: []},
          action: :create_manual_entry
        )

      updated =
        Ash.update!(
          member,
          %{username: "alice2", tree_name: "birke", key_targets: ["g16"]},
          action: :update_manual_entry
        )

      assert updated.username == "alice2"
      assert updated.tree_name == "birke"
      assert updated.key_targets == ["g16"]
    end

    test "rejects unknown key targets" do
      member =
        Ash.create!(Member, %{username: "alice", tree_name: "aloe", key_targets: []},
          action: :create_manual_entry
        )

      assert {:error, _} =
               Ash.update(member, %{key_targets: ["nope"]}, action: :update_manual_entry)
    end
  end

  describe ":change_keyholder_status action" do
    test "updates key_targets" do
      member = member_fixture(%{key_targets: []})

      with_key =
        Ash.update!(member, %{key_targets: ["g16"]}, action: :change_keyholder_status)

      assert with_key.key_targets == ["g16"]

      without_key =
        Ash.update!(with_key, %{key_targets: []}, action: :change_keyholder_status)

      assert without_key.key_targets == []
    end

    test "rejects unknown key targets" do
      member = member_fixture(%{key_targets: []})

      assert {:error, _} =
               Ash.update(member, %{key_targets: ["nope"]}, action: :change_keyholder_status)
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
