defmodule Valkyrie.Members.Member do
  use Ash.Resource,
    domain: Valkyrie.Members,
    extensions: [AshPaperTrail.Resource],
    data_layer: AshSqlite.DataLayer

  paper_trail do
    primary_key_type :uuid
    change_tracking_mode :full_diff
    store_action_name? true
    belongs_to_actor :user, destination: Valkyrie.Accounts.User, public?: true
    on_actions [:create_manual_entry, :update_manual_entry, :change_keyholder_status]
    create_version_on_destroy? false
  end

  sqlite do
    table "members"
    repo Valkyrie.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :username,
        :xhain_account_id,
        :has_key,
        :ssh_public_key,
        :tree_name,
        :is_active,
        :is_manual_entry
      ]

      upsert? true
      upsert_identity :unique_username
    end

    create :create_manual_entry do
      accept [
        :username,
        :tree_name,
        :ssh_public_key,
        :has_key
      ]

      upsert? true
      upsert_identity :unique_username

      change fn changeset, _ ->
        Ash.Changeset.change_attributes(changeset, %{is_manual_entry: true, is_active: true})
      end
    end

    update :update_manual_entry do
      accept [
        :username,
        :tree_name,
        :ssh_public_key,
        :has_key
      ]
    end

    update :change_keyholder_status do
      accept [:has_key]
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

    attribute :has_key, :boolean do
      description "Whether the member is a keyholder"
      allow_nil? false
      public? true
      default false
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
  end

  identities do
    identity :unique_username, [:username]
  end

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
