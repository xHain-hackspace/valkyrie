defmodule Valkyrie.Accounts do
  use Ash.Domain, otp_app: :valkyrie, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Valkyrie.Accounts.Token
    resource Valkyrie.Accounts.User
  end
end
