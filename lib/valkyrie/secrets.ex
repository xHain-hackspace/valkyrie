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

  def secret_for(
        [:authentication, :strategies, :xhain_account, :client_secret],
        Valkyrie.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:valkyrie, :xhain_account_client_secret)
  end

  def secret_for(
        [:authentication, :strategies, :xhain_account, :client_id],
        Valkyrie.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:valkyrie, :xhain_account_client_id)
  end

  def secret_for(
        [:authentication, :strategies, :xhain_account, :base_url],
        Valkyrie.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:valkyrie, :xhain_account_base_url)
  end
end
