defmodule Valkyrie.Members.Member do
  use Ash.Resource,
    domain: Valkyrie.Members,
    extensions: [AshPaperTrail.Resource, AshArchival.Resource],
    data_layer: AshSqlite.DataLayer

  paper_trail do
    primary_key_type :uuid
    change_tracking_mode :full_diff
    store_action_name? true
    belongs_to_actor :user, destination: Valkyrie.Accounts.User, public?: true

    # Access grants/revocations are audited on the `KeyTargetAccess` join resource,
    # so `change_keyholder_status` (which only manages that relationship) is not
    # tracked here.
    on_actions [
      :create_manual_entry,
      :update_manual_entry,
      :sync_update
    ]

    ignore_actions [:create]
    create_version_on_destroy? true
  end

  archive do
    exclude_read_actions(:read_for_audit_log)
  end

  sqlite do
    table "members"
    repo Valkyrie.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :read_for_audit_log do
      description "Read a member for the audit log"
    end

    create :create do
      primary? true

      # Access (`key_targets`) is intentionally NOT managed here: this action is an
      # upsert used by the Authentik sync, and managing the relationship would wipe a
      # member's access on every sync. Grant access via `change_keyholder_status`.
      accept [
        :username,
        :xhain_account_id,
        :ssh_public_key,
        :tree_name,
        :is_active,
        :is_manual_entry,
        :matrix_contact,
        :email
      ]

      upsert? true
      upsert_identity :unique_username

      change fn changeset, _ ->
        Ash.Changeset.change_attribute(changeset, :archived_at, nil)
      end
    end

    create :create_manual_entry do
      accept [
        :username,
        :tree_name,
        :ssh_public_key,
        :matrix_contact
      ]

      argument :key_target_ids, {:array, :uuid}, default: []

      upsert? true
      upsert_identity :unique_username

      change fn changeset, _ ->
        Ash.Changeset.change_attributes(changeset, %{
          is_manual_entry: true,
          is_active: true,
          archived_at: nil
        })
      end

      change manage_relationship(:key_target_ids, :key_targets, type: :append_and_remove)
    end

    update :sync_update do
      accept [
        :username,
        :xhain_account_id,
        :ssh_public_key,
        :tree_name,
        :is_active,
        :matrix_contact,
        :email
      ]
    end

    update :update_manual_entry do
      require_atomic? false

      accept [
        :username,
        :tree_name,
        :ssh_public_key,
        :matrix_contact
      ]

      argument :key_target_ids, {:array, :uuid}, default: []

      change manage_relationship(:key_target_ids, :key_targets, type: :append_and_remove)
    end

    # Sets a member's access to exactly the given set of key targets (by id).
    # Referential integrity is enforced by the join resource's foreign keys, so no
    # slug validation is needed — an unknown id simply cannot be related.
    update :change_keyholder_status do
      require_atomic? false

      argument :key_target_ids, {:array, :uuid}, allow_nil?: false

      change manage_relationship(:key_target_ids, :key_targets, type: :append_and_remove)
    end
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :created_at
    update_timestamp :updated_at

    attribute :username, :string do
      description "The username of the member"
      allow_nil? false
      public? true
    end

    attribute :xhain_account_id, :integer do
      description "The xHain Account ID of the member"
      allow_nil? false
      public? true
      # -1 indicates a manual entry
      default -1
    end

    attribute :tree_name, :string do
      description "The tree name of the member"
      allow_nil? false
      public? true
    end

    attribute :ssh_public_key, :string do
      description "The SSH public key of the member"
      allow_nil? true
      public? true
      constraints allow_empty?: true, trim?: true
      default ""
    end

    attribute :is_manual_entry, :boolean do
      description "Whether the member is a manual entry"
      allow_nil? false
      public? true
      default false
    end

    attribute :is_active, :boolean do
      description "Whether the member is active"
      allow_nil? false
      public? true
      default false
    end

    attribute :matrix_contact, :string do
      description "Matrix account. Either the default account or an external matrix account."
      allow_nil? true
      public? true
    end

    attribute :email, :string do
      description "The email address of the member, used for notifications."
      allow_nil? true
      public? true
    end
  end

  relationships do
    has_many :key_target_accesses, Valkyrie.Members.KeyTargetAccess

    many_to_many :key_targets, Valkyrie.Members.KeyTarget do
      description "The key access targets this member has access to."
      through Valkyrie.Members.KeyTargetAccess
      source_attribute_on_join_resource :member_id
      destination_attribute_on_join_resource :key_target_id
      public? true
    end
  end

  identities do
    identity :unique_username, [:username], where: expr(is_nil(archived_at))
  end

  @doc """
  Whether the member has access to at least one key target.
  Requires the `:key_targets` relationship to be loaded.
  """
  def keyholder?(%{key_targets: targets}) when is_list(targets), do: targets != []

  @doc """
  Whether the member has access to the key target with the given slug.
  Requires the `:key_targets` relationship to be loaded.
  """
  def keyholder?(%{key_targets: targets}, slug) when is_list(targets),
    do: Enum.any?(targets, &(&1.slug == slug))

  def ssh_public_key_valid?(nil), do: false
  def ssh_public_key_valid?(""), do: false

  def ssh_public_key_valid?(ssh_public_key) do
    case :ssh_file.decode(ssh_public_key, :public_key) do
      {:error, _} ->
        false

      _ ->
        true
    end
  end
end
