defmodule Valkyrie.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Valkyrie.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:valkyrie, :token_signing_secret)
  end
end
