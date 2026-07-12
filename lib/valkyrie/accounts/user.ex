defmodule Valkyrie.Accounts.User do
  use Ash.Resource,
    otp_app: :valkyrie,
    domain: Valkyrie.Accounts,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  sqlite do
    table "users"
    repo Valkyrie.Repo
  end

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

    tokens do
      enabled? true
      token_resource Valkyrie.Accounts.Token
      signing_secret Valkyrie.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      oidc :xhain_account do
        client_id Valkyrie.Secrets
        base_url Valkyrie.Secrets

        redirect_uri fn _secret, _context ->
          Application.fetch_env(:valkyrie, :xhain_account_redirect_uri)
        end

        registration_enabled? true
        id_token_signed_response_alg "HS256"
        authorization_params scope: "openid profile email groups"

        client_secret Valkyrie.Secrets
      end
    end
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    create :register_with_xhain_account do
      description "Register a user using the xHain Account System"
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false
      change AshAuthentication.GenerateTokenChange

      change fn changeset, _ ->
        user_info = Ash.Changeset.get_argument(changeset, :user_info)

        Ash.Changeset.change_attributes(changeset, %{
          username: Map.get(user_info, "preferred_username"),
          is_admin: admin?(user_info)
        })
      end

      upsert? true
      upsert_identity :username
    end

    read :sign_in_with_xhain_account do
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false
      prepare AshAuthentication.Strategy.OAuth2.SignInPreparation

      filter expr(username == get_path(^arg(:user_info), [:preferred_username]))
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :username, :string, allow_nil?: false, public?: true
    attribute :is_admin, :boolean, allow_nil?: false, default: false, public?: false
  end

  identities do
    identity :username, [:username]
  end

  # Whether the OIDC `groups` claim includes the configured admin group.
  # Missing config or claim → not an admin (fail closed).
  defp admin?(user_info) do
    groups = Map.get(user_info, "groups", [])
    admin_group = Application.get_env(:valkyrie, :authentik_admin_group)

    admin_group != nil and admin_group in groups
  end
end
