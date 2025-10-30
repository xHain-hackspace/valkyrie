import Config
config :valkyrie, token_signing_secret: "h+Y51jGCFZWAceJy8mv7XXKJXQOBRKki"
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :valkyrie, Valkyrie.Repo,
  database: Path.expand("../valkyrie_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :valkyrie, ValkyrieWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "xrquRQbSXWKVqe73jGpMFzw17kpu5PnbZdZJlS6A0QQFcOVxSczpqMEMcAzPhoau",
  server: false

# In test we don't send emails
config :valkyrie, Valkyrie.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
