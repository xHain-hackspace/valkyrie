defmodule Valkyrie.MemberHelpers do
  alias Valkyrie.Members
  alias Valkyrie.Members.KeyTarget
  alias Valkyrie.Members.KeyTargets
  alias Valkyrie.Members.Member

  @valid_ssh_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOn6J0bzZLnNNvMVDzyP63RNQjdT3BgBRZLm2wO+9sZl"

  # The standard set of doors used across tests. `g16` is already seeded by the
  # base migration; `ensure_key_targets/0` tops up the rest idempotently.
  @default_targets [{"g16", "xHain G16"}, {"g18", "xHain G18"}, {"g20", "Lichtung"}]

  @doc """
  Ensure the standard set of key targets exists (idempotent). Call in `setup` for
  tests that grant access by slug. Created without granting existing keyholders,
  so seeding has no side effects on member access.
  """
  def ensure_key_targets(targets \\ @default_targets) do
    existing = MapSet.new(KeyTargets.slugs())

    for {slug, name} <- targets, not MapSet.member?(existing, slug) do
      Ash.create!(KeyTarget, %{slug: slug, name: name, grant_to_all_keyholders: false},
        action: :create
      )
    end

    KeyTargets.all()
  end

  @doc """
  Create a `KeyTarget` (a door). Does not grant it to existing keyholders unless
  `grant_to_all_keyholders: true` is passed.
  """
  def key_target_fixture(attrs \\ %{}) do
    defaults = %{slug: "garden", name: "Garden", grant_to_all_keyholders: false}
    Ash.create!(KeyTarget, Map.merge(defaults, Map.new(attrs)), action: :create)
  end

  @doc """
  Create a member. `:key_targets` (a list of slugs) grants access via the
  relationship after creation; the referenced targets must already exist. Defaults
  to granting every currently-seeded target (preserving the previous behaviour).
  """
  def member_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {slugs, attrs} = Map.pop(attrs, :key_targets, KeyTargets.slugs())

    defaults = %{
      username: "testuser",
      xhain_account_id: 1,
      tree_name: "birke",
      ssh_public_key: @valid_ssh_key,
      is_active: true
    }

    Member
    |> Ash.create!(Map.merge(defaults, attrs), action: :create)
    |> grant_targets(slugs)
  end

  defp grant_targets(member, []),
    do: Ash.load!(member, :key_targets)

  defp grant_targets(member, slugs) do
    targets = KeyTargets.all()

    ids =
      Enum.map(slugs, fn slug ->
        case Enum.find(targets, &(&1.slug == slug)) do
          %{id: id} ->
            id

          nil ->
            raise "key target #{inspect(slug)} not seeded; call ensure_key_targets/0 in setup"
        end
      end)

    {:ok, updated} =
      Members.change_keyholder_status(member, %{key_target_ids: ids}, load: [:key_targets])

    updated
  end

  def valid_ssh_key, do: @valid_ssh_key
end
