defmodule Valkyrie.Members.KeyTarget do
  @moduledoc """
  A key access target (e.g. a door or room). Each target has its own
  authorized_keys list served at `/authorized_keys/<slug>`. Access is a real
  database relation: a member is granted a target through the
  `Valkyrie.Members.KeyTargetAccess` join (`many_to_many :members`).

  Management: in development, targets are created/edited through AshAdmin. That
  admin UI is mounted behind `dev_routes` only, so **in production targets are
  seeded via migration** — adding or removing a target in prod means shipping a
  migration, not a runtime edit. The `slug` is the stable natural key (and URL
  identity), is immutable after creation, and must be URL-safe (`[a-z0-9-]`).
  Deleting a target removes every member's access to it via a database
  `ON DELETE CASCADE` on the join — no application code involved.
  """

  use Ash.Resource,
    domain: Valkyrie.Members,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshPaperTrail.Resource]

  require Ash.Query

  sqlite do
    table "key_targets"
    repo Valkyrie.Repo
  end

  paper_trail do
    primary_key_type :uuid
    change_tracking_mode :full_diff
    store_action_name? true
    belongs_to_actor :user, destination: Valkyrie.Accounts.User, public?: true
    create_version_on_destroy? true
    # Doors are hard-deleted, so the version must not keep a foreign key back to
    # the (deleted) source row.
    reference_source? false
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:slug, :name]

      # The slug is a URL path segment and (via `.sig`) a signature marker, so it
      # must be URL-safe: lowercase letters, digits and dashes only.
      validate match(:slug, ~r/^[a-z0-9-]+$/) do
        message "must contain only lowercase letters, numbers and dashes"
      end

      # Optionally grant the new target to everyone who is already a keyholder.
      # Defaults to false so only the door form (which opts in) mass-grants;
      # AshAdmin/seeds/other callers create a door without touching access.
      argument :grant_to_all_keyholders, :boolean, default: false

      change &grant_to_all_keyholders/2
    end

    # Slug is the natural key + URL identity, so it is immutable after creation.
    update :update do
      primary? true
      accept [:name]
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

  relationships do
    many_to_many :members, Valkyrie.Members.Member do
      through Valkyrie.Members.KeyTargetAccess
      source_attribute_on_join_resource :key_target_id
      destination_attribute_on_join_resource :member_id
      public? true
    end
  end

  identities do
    identity :unique_slug, [:slug]
  end

  @doc false
  # When `grant_to_all_keyholders` is set, grant the newly created target to every
  # member who is already a keyholder (has access to at least one other target).
  def grant_to_all_keyholders(changeset, context) do
    if Ash.Changeset.get_argument(changeset, :grant_to_all_keyholders) do
      Ash.Changeset.after_action(changeset, fn _changeset, target ->
        inputs =
          Valkyrie.Members.Member
          |> Ash.Query.filter(exists(key_target_accesses, true))
          |> Ash.read!(authorize?: false)
          |> Enum.map(&%{member_id: &1.id, key_target_id: target.id})

        # One bulk insert instead of a create per keyholder. Paper-trail versions
        # are still written per record (each grant is audited).
        Ash.bulk_create!(inputs, Valkyrie.Members.KeyTargetAccess, :create,
          actor: context.actor,
          return_records?: false,
          return_errors?: true
        )

        {:ok, target}
      end)
    else
      changeset
    end
  end
end
