import Config
config :valkyrie,
  token_signing_secret: "h+Y51jGCFZWAceJy8mv7XXKJXQOBRKki",
  disable_auth: true

# Wire Req.Test as the HTTP adapter for Authentik calls in tests
config :valkyrie, authentik_req_options: [plug: {Req.Test, :valkyrie_authentik}, retry: false]

# Dummy values for environment variables required by runtime.exs in all envs
System.put_env("AUTHENTIK_MEMBER_GROUP_UUID", "00000000-0000-0000-0000-000000000000")
System.put_env("AUTHENTIK_TOKEN", "test-token")
System.put_env("AUTHENTIK_URL", "http://authentik.test")
System.put_env("XHAIN_ACCOUNT_CLIENT_SECRET", "test-secret")
System.put_env("XHAIN_ACCOUNT_CLIENT_ID", "test-client-id")
System.put_env("XHAIN_ACCOUNT_BASE_URL", "http://account.test")
System.put_env("XHAIN_ACCOUNT_REDIRECT_URI", "http://localhost:4002/auth/callback")
System.put_env("XDOOR_SIGNING_KEY", """
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAylL6ZaL1sUmG3wyUqzwBTjwfyJKdgHj6sT1vSe3+QV0XaURU
Yu9w2du8PCvUogJkD9kdiHupyr8yXUXcP4c+oXXUWlHDr5sC31nsnOUQ3Q820JJE
fSJfty4jiNEiD9tCEX4hgWMX7MKJZC+VwCq35L4SaazFfKlA4bdBH1ZEJ/Q7Dcoj
htv3+jHh/4L+/8kr+SvOb8MDXhXOxy2+ULV546PAD7oLpjDTYk4MIXVyRQ03sZYU
Gbjfj7dVe/At9Xx+fbcra4FsKSZQ1A3EpV3ExnGn/17bGw917E3IWCul9QRKn0nA
x+FDSQLmlxOHmZE3RxYsJz8ioTFv6DLvnfT63QIDAQABAoIBAESu9qIaOB3/P/Ho
a2/V5vuQHZoRa7Z5W2Ff4a/PQ0kdOR1bPOp5Lm5G0hf7KSv2c9GNeyEiGfnh/k77
sFFAsFpPjc87gprSnJ8F//UjLh5dU9ZqUSXJzYR5/UYs+Ms5O6yEjQtHgI+3WrzQ
Cp454kOc4tNM+53eN1BozYq91lVZUPVGnMIZSnXWKvQo0vBY65oPwsfDq+mXrUnI
mpcS8VwbN8iLQvIbYMA7PxJWgZQHyOHNhC/WcMxzcjHw2oIkqN8Z3lhGMAyuGiPZ
GAhrrJCUJa/+xFSVf0B/8PwUgILDRoJNPUzZcn0ipDyiVZA7WcInXvEnCTqQPx5T
IPU8CmECgYEA81G9GkUxtviayQyRinFtaHyAShLF4gxktvjdwSM5DjXjX2QdJkCu
z+7XUJ0lbdC4CZBKXGv+jgzOPXt5RjUVc57VMMGR8VMF+agUQ3IwLV5JOF3Cg6v2
rAwh1+53rQqXvWqfWLtiDg9he7h+0Y/wx249HdhqN+XkK7BHlA2GMqMCgYEA1N5M
tq00pkZYxLGKu/nVC1ijc+QkBr9JLYN/WJcZdVrxZbCkCTxJjU4i4UlVlmvwsZBU
k+Z+kYwRJwlbylokFcgdMuI4SkqYTKe/vh8o7nC18Ro9wMvdjeFJGlfIFEOUfPCv
7yit+oLwG2+UxyFGHBt7PbWWG/Yy637d1YfQdH8CgYEAh8nP/L8s1W28BANNnbNb
WXpRpgUABfzgn/QW3Vgo2TNdpriaQ+TJKiWiZ8yrPLPEYSHzPczPDLs8xbcIoROy
2wmC9GiyZ7jrlr4kQNeS5169AgXhLdZkHPPQV08v3pQQxpagQsagHDSdNIxrycvI
laOB3AwQiw1y3qbL62X4xH0CgYAPFYGSIEvuzGVV6s7N6zIxj6Jlf/EdmUhyNTM8
79gZ/MvGTPISxXbg0HygQjYSZquzqWqU4Gxvm+FLRtp+SEzuTjPjeyxJ92c7Z1eq
/UJFQy9hWl6t3sRgXWp0t2uyI+fNwrB03gkWC1lAWHPOeIkjTL867Dcq3BNXpLHL
g8g9uQKBgQCLrWUGWSR8sUHksgHjWEhVnax8IHhIpg3oNfbaYGH+qglOUeo0rbn6
1ORC29bBuC9B/dfVVC/BwuyfCdnCiL/U23LXf+YrgSRJyhXRc2wX5QHFMPABROU3
h8S8wZ8D0/6l8233+SyCKyJErps+gOXWfn6VRhs/xmNyqBflAx07mg==
-----END RSA PRIVATE KEY-----
""")
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
