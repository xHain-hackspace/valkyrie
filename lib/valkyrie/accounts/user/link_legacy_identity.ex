defmodule Valkyrie.Accounts.User.LinkLegacyIdentity do
  @moduledoc """
  Links users that were created before identities (`iss`/`sub`) were stored.

  Such users were matched by username only, so they have no identity row yet and
  `AshAuthentication.Strategy.OAuth2.IdentityChange` would refuse their sign-in.
  On sign-in, if the username matches a user that has no identity for this
  strategy, and the `sub` is not linked to anyone yet, the identity is created up
  front so the regular resolver attaches the sign-in to that user.

  Authentik is our own IdP and owns usernames, so trusting the username for this
  one-time link keeps the previous behaviour. Once linked, a different `sub` for
  the same username is rejected. Must be listed before `IdentityChange`.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias AshAuthentication.Strategy.OAuth2
  alias AshAuthentication.UserIdentity
  alias Valkyrie.Accounts.User
  alias Valkyrie.Accounts.UserIdentity, as: Identity

  @strategy :xhain_account

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &link/1)
  end

  defp link(changeset) do
    user_info = Ash.Changeset.get_argument(changeset, :user_info)
    username = Ash.Changeset.get_attribute(changeset, :username)

    with uid when not is_nil(uid) <- OAuth2.uid_from_user_info(user_info),
         false <- identity_exists?(uid: uid),
         %User{} = user <- get_user(username),
         false <- identity_exists?(user_id: user.id),
         {:ok, _identity} <-
           UserIdentity.Actions.upsert(Identity, %{
             user_id: user.id,
             user_info: user_info,
             oauth_tokens: Ash.Changeset.get_argument(changeset, :oauth_tokens),
             strategy: @strategy
           }) do
      changeset
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
      _ -> changeset
    end
  end

  defp identity_exists?(filter) do
    Identity
    |> Ash.Query.filter(strategy == ^to_string(@strategy))
    |> Ash.Query.filter(^filter)
    |> Ash.exists?(authorize?: false)
  end

  defp get_user(nil), do: nil

  defp get_user(username) do
    User
    |> Ash.Query.filter(username == ^username)
    |> Ash.read_one!(authorize?: false)
  end
end
