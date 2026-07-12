defmodule Valkyrie.Repo.Migrations.ReplaceHasKeyWithKeyTargets do
  @moduledoc """
  Replaces the boolean `has_key` keyholder flag with a per-target `key_targets`
  slug list, and introduces the `key_targets` table (managed via AshAdmin) as the
  source of truth for target definitions. Existing keyholders are migrated to
  having access to all seeded targets.
  """

  use Ecto.Migration

  @targets [
    {"g16", "xHain G16"}
  ]

  def up do
    alter table(:members) do
      add :key_targets, {:array, :text}, null: false, default: []
    end

    flush()

    # Existing keyholders gain access to all targets; everyone else gets none.
    execute """
    UPDATE members
    SET key_targets = '["g16"]'
    WHERE has_key = 1
    """

    alter table(:members) do
      remove :has_key
    end

    create table(:key_targets, primary_key: false) do
      add :name, :text, null: false
      add :slug, :text, null: false
      add :updated_at, :utc_datetime_usec, null: false
      add :created_at, :utc_datetime_usec, null: false
      add :id, :uuid, null: false, primary_key: true
    end

    create unique_index(:key_targets, [:slug], name: "key_targets_unique_slug_index")

    flush()

    now = DateTime.utc_now() |> DateTime.to_iso8601()

    for {slug, name} <- @targets do
      execute """
      INSERT INTO key_targets (id, slug, name, created_at, updated_at)
      VALUES ('#{Ecto.UUID.generate()}', '#{slug}', '#{name}', '#{now}', '#{now}')
      """
    end
  end

  def down do
    drop_if_exists unique_index(:key_targets, [:slug], name: "key_targets_unique_slug_index")
    drop table(:key_targets)

    alter table(:members) do
      add :has_key, :boolean, null: false, default: false
    end

    flush()

    # Anyone with access to at least one target is a keyholder again.
    execute """
    UPDATE members
    SET has_key = 1
    WHERE key_targets != '[]'
    """

    alter table(:members) do
      remove :key_targets
    end
  end
end
