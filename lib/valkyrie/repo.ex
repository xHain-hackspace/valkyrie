defmodule Valkyrie.Repo do
  use AshSqlite.Repo,
    otp_app: :valkyrie
end
