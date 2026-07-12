defmodule Valkyrie.Members.KeyTargetAccess do
  @moduledoc """
  Join resource linking a `Member` to a `KeyTarget` they have access to.

  This replaces the former denormalised `Member.key_targets` slug array: access is
  now a real database relation keyed on `KeyTarget.id`, so referential integrity is
  enforced by the database. Deleting a member or a key target cascades to the
  matching rows here via `ON DELETE CASCADE` (see the `references` block) — no
  application code is required to keep access consistent.

  Grants and revocations are audited via paper trail.
  """

  use Ash.Resource,
    domain: Valkyrie.Members,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshPaperTrail.Resource]

  sqlite do
    table "member_key_targets"
    repo Valkyrie.Repo

    references do
      reference :member, on_delete: :delete
      reference :key_target, on_delete: :delete
    end
  end

  paper_trail do
    primary_key_type :uuid
    change_tracking_mode :full_diff
    store_action_name? true
    belongs_to_actor :user, destination: Valkyrie.Accounts.User, public?: true
    create_version_on_destroy? true
    # Join rows are hard-deleted (on revoke, and via FK cascade on door deletion),
    # so the version must not keep a foreign key back to the (deleted) source row.
    reference_source? false
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:member_id, :key_target_id]
    end
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :created_at
  end

  relationships do
    belongs_to :member, Valkyrie.Members.Member, allow_nil?: false, public?: true
    belongs_to :key_target, Valkyrie.Members.KeyTarget, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_access, [:member_id, :key_target_id]
  end
end
