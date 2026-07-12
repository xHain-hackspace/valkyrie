defmodule Valkyrie.Members.KeyTargetTest do
  use Valkyrie.DataCase, async: false

  alias Valkyrie.Members.KeyTarget
  alias Valkyrie.Members.KeyTargets
  alias Valkyrie.Members.Member

  describe "adding a target at runtime" do
    test "a newly created KeyTarget becomes a valid slug immediately" do
      Ash.create!(KeyTarget, %{slug: "garden", name: "Garden"})

      assert "garden" in KeyTargets.slugs()
      assert KeyTargets.valid_slug?("garden")
      assert KeyTargets.name_for("garden") == "Garden"
    end

    test "a member can be granted a newly created target" do
      Ash.create!(KeyTarget, %{slug: "garden", name: "Garden"})

      member =
        Ash.create!(
          Member,
          %{username: "alice", tree_name: "aloe", key_targets: ["garden"]},
          action: :create_manual_entry
        )

      assert member.key_targets == ["garden"]
    end

    test "slug must be unique" do
      Ash.create!(KeyTarget, %{slug: "garden", name: "Garden"})

      assert {:error, _} = Ash.create(KeyTarget, %{slug: "garden", name: "Garden Two"})
    end
  end

  describe "deleting a target" do
    test "scrubs the slug from every member that references it" do
      target = Ash.create!(KeyTarget, %{slug: "garden", name: "Garden"})

      member =
        Ash.create!(
          Member,
          %{username: "alice", tree_name: "aloe", key_targets: ["garden"]},
          action: :create_manual_entry
        )

      Ash.destroy!(target)

      refute "garden" in KeyTargets.slugs()

      reloaded = Ash.get!(Member, member.id, authorize?: false)
      refute "garden" in reloaded.key_targets
    end

    test "leaves other granted targets intact" do
      Ash.create!(KeyTarget, %{slug: "garden", name: "Garden"})

      member =
        Ash.create!(
          Member,
          %{username: "alice", tree_name: "aloe", key_targets: ["g16", "garden"]},
          action: :create_manual_entry
        )

      "garden" |> target_by_slug() |> Ash.destroy!()

      reloaded = Ash.get!(Member, member.id, authorize?: false)
      assert reloaded.key_targets == ["g16"]
    end

    test "records the revocation as an audited member change" do
      target = Ash.create!(KeyTarget, %{slug: "garden", name: "Garden"})

      member =
        Ash.create!(
          Member,
          %{username: "alice", tree_name: "aloe", key_targets: ["garden"]},
          action: :create_manual_entry
        )

      Ash.destroy!(target)

      {:ok, page} =
        Valkyrie.Members.list_versions(
          page: [limit: 100],
          query: [
            filter: [version_source_id: member.id],
            sort: [version_inserted_at: :desc]
          ]
        )

      assert :change_keyholder_status in Enum.map(page.results, & &1.version_action_name)
    end
  end

  describe "immutable slug" do
    test "the update action rejects a slug change but allows a name change" do
      target = Ash.create!(KeyTarget, %{slug: "garden", name: "Garden"})

      assert {:error, _} = Ash.update(target, %{slug: "yard"}, action: :update)

      renamed = Ash.update!(target, %{name: "Back Garden"}, action: :update)
      assert renamed.slug == "garden"
      assert renamed.name == "Back Garden"
    end
  end

  defp target_by_slug(slug) do
    KeyTarget
    |> Ash.read!()
    |> Enum.find(&(&1.slug == slug))
  end
end
