defmodule Valkyrie.Members.KeyTargetTest do
  use Valkyrie.DataCase, async: false

  alias Valkyrie.Members.KeyTarget
  alias Valkyrie.Members.KeyTargetAccess
  alias Valkyrie.Members.KeyTargets
  alias Valkyrie.Members.Member

  setup do
    ensure_key_targets()
    :ok
  end

  defp target_slugs(member),
    do: member |> Ash.load!(:key_targets) |> Map.fetch!(:key_targets) |> Enum.map(& &1.slug)

  describe "adding a target at runtime" do
    test "a newly created KeyTarget becomes a valid slug immediately" do
      key_target_fixture(%{slug: "garden", name: "Garden"})

      assert "garden" in KeyTargets.slugs()
      assert KeyTargets.valid_slug?("garden")
      assert KeyTargets.name_for("garden") == "Garden"
    end

    test "a member can be granted a newly created target" do
      target = key_target_fixture(%{slug: "garden", name: "Garden"})

      member =
        Ash.create!(
          Member,
          %{username: "alice", tree_name: "aloe", key_target_ids: [target.id]},
          action: :create_manual_entry
        )

      assert target_slugs(member) == ["garden"]
    end

    test "slug must be unique" do
      key_target_fixture(%{slug: "garden", name: "Garden"})

      assert {:error, _} =
               Ash.create(KeyTarget, %{slug: "garden", name: "Garden Two"}, action: :create)
    end
  end

  describe "grant_to_all_keyholders on create" do
    test "grants the new target to every existing keyholder when requested" do
      keyholder = member_fixture(%{username: "kh", key_targets: ["g16"]})
      non_keyholder = member_fixture(%{username: "nkh", xhain_account_id: 2, key_targets: []})

      Ash.create!(KeyTarget, %{slug: "garden", name: "Garden", grant_to_all_keyholders: true},
        action: :create
      )

      assert "garden" in target_slugs(keyholder)
      refute "garden" in target_slugs(non_keyholder)
    end

    test "each keyholder grant is audited" do
      member_fixture(%{username: "kh", key_targets: ["g16"]})

      before = Ash.count!(KeyTargetAccess.Version, authorize?: false)

      Ash.create!(KeyTarget, %{slug: "garden", name: "Garden", grant_to_all_keyholders: true},
        action: :create
      )

      assert Ash.count!(KeyTargetAccess.Version, authorize?: false) > before
    end

    test "grants no one by default (arg absent)" do
      keyholder = member_fixture(%{username: "kh", key_targets: ["g16"]})

      Ash.create!(KeyTarget, %{slug: "garden", name: "Garden"}, action: :create)

      refute "garden" in target_slugs(keyholder)
    end

    test "grants no one when set to false" do
      keyholder = member_fixture(%{username: "kh", key_targets: ["g16"]})

      key_target_fixture(%{slug: "garden", name: "Garden"})

      refute "garden" in target_slugs(keyholder)
    end
  end

  describe "slug validation" do
    test "rejects non-URL-safe slugs" do
      for bad <- ["a.sig", "a/b", "A16", "has space", "under_score"] do
        assert {:error, _} =
                 Ash.create(KeyTarget, %{slug: bad, name: "X"}, action: :create),
               "expected #{inspect(bad)} to be rejected"
      end
    end

    test "accepts lowercase, digits and dashes" do
      assert %KeyTarget{slug: "g-16"} =
               Ash.create!(KeyTarget, %{slug: "g-16", name: "G16"}, action: :create)
    end
  end

  describe "referential integrity" do
    test "cannot grant access to a non-existent key target" do
      member = member_fixture(%{username: "alice", key_targets: []})

      assert {:error, _} =
               Ash.create(KeyTargetAccess, %{
                 member_id: member.id,
                 key_target_id: Ecto.UUID.generate()
               })
    end

    test "the same target cannot be granted to a member twice" do
      target = key_target_fixture(%{slug: "garden", name: "Garden"})
      member = member_fixture(%{username: "alice", key_targets: []})

      Ash.create!(KeyTargetAccess, %{member_id: member.id, key_target_id: target.id})

      assert {:error, _} =
               Ash.create(KeyTargetAccess, %{member_id: member.id, key_target_id: target.id})
    end
  end

  describe "deleting a target cascades access removal (database-enforced)" do
    test "removes the join rows and the members' access, leaving other targets intact" do
      target = key_target_fixture(%{slug: "garden", name: "Garden"})
      member = member_fixture(%{username: "alice", key_targets: ["g16", "garden"]})

      Ash.destroy!(target)

      refute "garden" in KeyTargets.slugs()
      assert target_slugs(member) == ["g16"]

      # The cascade is the database's job: no join rows reference the deleted target.
      refute KeyTargetAccess |> Ash.read!() |> Enum.any?(&(&1.key_target_id == target.id))
    end

    test "records the door deletion as an audited KeyTarget version" do
      target = key_target_fixture(%{slug: "garden", name: "Garden"})

      Ash.destroy!(target)

      versions = Ash.read!(KeyTarget.Version)

      assert Enum.any?(
               versions,
               &(&1.version_source_id == target.id and &1.version_action_type == :destroy)
             )
    end
  end

  describe "access changes are audited" do
    test "granting a target records a create version on the join" do
      target = key_target_fixture(%{slug: "garden", name: "Garden"})
      member = member_fixture(%{username: "alice", key_targets: []})

      Ash.update!(member, %{key_target_ids: [target.id]}, action: :change_keyholder_status)

      versions = Ash.read!(KeyTargetAccess.Version)
      assert Enum.any?(versions, &(&1.version_action_type == :create))
    end
  end

  describe "immutable slug" do
    test "the update action rejects a slug change but allows a name change" do
      target = key_target_fixture(%{slug: "garden", name: "Garden"})

      assert {:error, _} = Ash.update(target, %{slug: "yard"}, action: :update)

      renamed = Ash.update!(target, %{name: "Back Garden"}, action: :update)
      assert renamed.slug == "garden"
      assert renamed.name == "Back Garden"
    end
  end
end
