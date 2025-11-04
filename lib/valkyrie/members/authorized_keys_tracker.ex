defmodule Valkyrie.Members.LastAccess do
  use Ash.Resource,
    domain: Valkyrie.Members,
    data_layer: Ash.DataLayer.Ets,
    notifiers: [Ash.Notifier.PubSub]

  ets do
    private? false
  end

  actions do
    defaults [:read]
    create :access do
      primary? true
      accept [:resource_name]

      change fn changeset, _ ->
        Ash.Changeset.change_attributes(changeset, %{last_access: DateTime.utc_now()})
      end
      upsert? true
      upsert_identity :unique_resource_name
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :resource_name, :string do
      allow_nil? false
      public? true
    end

    attribute :last_access, :utc_datetime do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_resource_name, [:resource_name], pre_check?: true
  end

  pub_sub do
    module ValkyrieWeb.Endpoint
    prefix "last_access"

    publish :access, [:resource_name, nil]
  end
end
