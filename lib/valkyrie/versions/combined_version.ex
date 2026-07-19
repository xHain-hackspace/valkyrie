defmodule Valkyrie.Versions.CombinedVersion do
  use Ash.Resource,
    domain: Valkyrie.Versions,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "combined_versions"
    repo Valkyrie.Repo
    # this table isn't managed by the migration generator
    migrate? false
  end

  actions do
    # no create/update/destroy — the view isn't writable
    defaults [:read]
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :kind, :string, primary_key?: true, allow_nil?: false
    attribute :inserted_at, :utc_datetime_usec, source: :version_inserted_at
    attribute :user_id, :uuid
    attribute :action, :string, source: :version_action_name
    attribute :version_action_type, :string
    attribute :version_source_id, :uuid
    attribute :changes, :map
    # Extracted by the view (json_extract) so both member- and access-kind rows are
    # filterable by the affected member / door in SQL.
    attribute :member_id, :uuid
    attribute :key_target_id, :uuid
  end

  relationships do
    belongs_to :actor, Valkyrie.Accounts.User do
      source_attribute :user_id
      destination_attribute :id
      # this resource is read-only anyway
      attribute_writable? false
    end
  end

end
