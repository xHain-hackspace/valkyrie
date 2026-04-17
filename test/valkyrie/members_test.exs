defmodule Valkyrie.MembersTest do
  use Valkyrie.DataCase, async: false

  import Valkyrie.AuthentikHelpers

  alias Valkyrie.Members
  alias Valkyrie.Members.Member
  alias Valkyrie.Members.SyncState

  # UUID configured in config/test.exs as the member group
  @member_group_uuid "00000000-0000-0000-0000-000000000000"

  setup do
    SyncState.finish_sync()
    Phoenix.PubSub.subscribe(Valkyrie.PubSub, "sync_members:progress")
    :ok
  end

  defp sync do
    Members.update_members_from_xhain_account_system()
  end

  defp active_user(attrs) do
    user_fixture(Map.merge(%{"groups" => [@member_group_uuid]}, attrs))
  end

  describe "update_members_from_xhain_account_system/0" do
    test "creates a new member for a user returned by Authentik" do
      stub_authentik(page_response([active_user(%{"username" => "alice", "pk" => 42})]))

      sync()

      members = Ash.read!(Member)
      assert length(members) == 1
      assert hd(members).username == "alice"
      assert hd(members).xhain_account_id == 42
    end

    test "updates an existing member when a sync field changes" do
      existing = member_fixture(%{username: "alice", ssh_public_key: valid_ssh_key()})

      new_key =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4sRl6gkKsKOqygMQvj/5MbTlMFnUYfSjYaQjqT/bAU"

      stub_authentik(
        page_response([
          active_user(%{"username" => "alice", "pk" => existing.xhain_account_id,
            "attributes" => %{"ssh-key" => new_key, "tree" => "aloe"}})
        ])
      )

      sync()

      [member] = Ash.read!(Member)
      assert member.ssh_public_key == new_key
    end

    test "does not update a member when no sync fields change" do
      member_fixture(%{
        username: "alice",
        xhain_account_id: 42,
        tree_name: "aloe",
        is_active: true,
        ssh_public_key: valid_ssh_key()
      })

      stub_authentik(
        page_response([
          active_user(%{
            "username" => "alice",
            "pk" => 42,
            "attributes" => %{"ssh-key" => valid_ssh_key(), "tree" => "aloe"}
          })
        ])
      )

      sync()

      [member] = Ash.read!(Member)
      assert member.username == "alice"
    end

    test "soft-deletes a member that no longer appears in Authentik" do
      existing = member_fixture(%{username: "alice"})

      stub_authentik(page_response([]))

      sync()

      members = Ash.read!(Member)
      assert Enum.empty?(members)

      archived = Ash.read!(Member, action: :read_for_audit_log)
      assert Enum.any?(archived, &(&1.id == existing.id))
    end

    test "does not archive manual entries when they are absent from Authentik" do
      Ash.create!(Member, %{username: "manual-user", tree_name: "manualtree"},
        action: :create_manual_entry
      )

      stub_authentik(page_response([]))

      sync()

      members = Ash.read!(Member)
      assert length(members) == 1
      assert hd(members).username == "manual-user"
    end

    test "skips users with missing tree_name" do
      stub_authentik(
        page_response([
          user_fixture(%{"attributes" => %{"ssh-key" => valid_ssh_key()}})
        ])
      )

      sync()

      assert Enum.empty?(Ash.read!(Member))
    end

    test "skips users with missing username" do
      stub_authentik(
        page_response([
          user_fixture(%{"username" => nil})
        ])
      )

      sync()

      assert Enum.empty?(Ash.read!(Member))
    end

    test "sets is_active true for users in the member group" do
      stub_authentik(
        page_response([active_user(%{"username" => "alice"})])
      )

      sync()

      [member] = Ash.read!(Member)
      assert member.is_active == true
    end

    test "sets is_active false for users not in the member group" do
      stub_authentik(
        page_response([user_fixture(%{"username" => "alice", "groups" => []})])
      )

      sync()

      [member] = Ash.read!(Member)
      assert member.is_active == false
    end

    test "broadcasts error progress when Authentik API fails" do
      Req.Test.stub(:valkyrie_authentik, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      sync()

      assert_receive {:sync_progress, %{status: :error}}, 500
    end

    test "rejects sync when one is already running" do
      :ok = SyncState.start_sync()

      assert {:error, :already_syncing} = sync()
    end
  end
end
