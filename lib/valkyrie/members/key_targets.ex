defmodule Valkyrie.Members.KeyTargets do
  @moduledoc """
  Key access targets are the distinct authorized_keys lists a member can be
  granted access to (e.g. doors or rooms). They are stored in the database as
  `Valkyrie.Members.KeyTarget` rows and managed via AshAdmin.

  A member's `key_targets` attribute holds the slugs they have access to.
  """

  alias Valkyrie.Members.KeyTarget

  @doc "All targets as `KeyTarget` structs, sorted by name."
  def all do
    KeyTarget
    |> Ash.read!()
    |> Enum.sort_by(& &1.name)
  end

  @doc "All target slugs."
  def slugs do
    Enum.map(all(), & &1.slug)
  end

  @doc "Whether the given slug is an existing target."
  def valid_slug?(slug) do
    slug in slugs()
  end

  @doc "Human-readable name for a slug, or the slug itself if unknown."
  def name_for(slug) do
    case Enum.find(all(), &(&1.slug == slug)) do
      %{name: name} -> name
      _ -> slug
    end
  end
end
