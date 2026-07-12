defmodule Valkyrie.Members.KeyTarget do
  @moduledoc """
  A key access target (e.g. a door or room). Each target has its own
  authorized_keys list served at `/authorized_keys/<slug>`; members are granted
  access per target via their `key_targets` slug array.

  Management: in development, targets are created/edited through AshAdmin. That
  admin UI is mounted behind `dev_routes` only, so **in production targets are
  seeded via migration** — adding or removing a target in prod means shipping a
  migration, not a runtime edit. The `slug` is the stable natural key (and URL
  identity) and is immutable after creation; deleting a target scrubs its slug
  from every member that references it.
  """

  use Ash.Resource,
    domain: Valkyrie.Members,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "key_targets"
    repo Valkyrie.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:slug, :name]
    end

    # Slug is the natural key + URL identity, so it is immutable after creation.
    update :update do
      primary? true
      accept [:name]
    end

    # Deleting a target scrubs its slug from every member that references it, so
    # no orphan slugs are left behind.
    destroy :destroy do
      primary? true
      require_atomic? false

      change fn changeset, context ->
        Ash.Changeset.after_action(changeset, fn _changeset, target ->
          Valkyrie.Members.Member
          |> Ash.read!()
          |> Enum.filter(&(target.slug in &1.key_targets))
          |> Enum.each(fn member ->
            Ash.update!(member, %{key_targets: member.key_targets -- [target.slug]},
              action: :change_keyholder_status,
              actor: context.actor
            )
          end)

          {:ok, target}
        end)
      end
    end
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :created_at
    update_timestamp :updated_at

    attribute :slug, :string do
      description "URL-safe identifier of the key access target, used in /authorized_keys/<slug>"
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      description "Human-readable name of the key access target"
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
