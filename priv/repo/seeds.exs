# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Valkyrie.Repo.insert!(%Valkyrie.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Ensure the "authentik" system user exists — used as the actor for sync-driven audit log entries.
Valkyrie.Repo.insert!(
  %Valkyrie.Accounts.User{id: Ecto.UUID.generate(), username: "authentik"},
  on_conflict: :nothing,
  conflict_target: [:username]
)
