defmodule Valkyrie.Accounts.UserIdentity do
  use Ash.Resource,
    otp_app: :valkyrie,
    domain: Valkyrie.Accounts,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication.UserIdentity]

  sqlite do
    table "user_identities"
    repo Valkyrie.Repo
  end

  user_identity do
    user_resource Valkyrie.Accounts.User
  end

  actions do
    defaults [:read]
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end
end
