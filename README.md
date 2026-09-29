# Valkyrie

Valkyrie manages door access for the [xHain hackspace](https://x-hain.de). It
syncs members from the xHain account system (Authentik). Admins use it to grant
members access to individual doors. For every door it publishes a signed
`authorized_keys` file, and the xDoor devices pull that file to decide whose SSH
key can open them.

It's a Phoenix LiveView application built on [Ash](https://ash-hq.org) with a
SQLite database.

For how the pieces fit together, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Features

- **Member list**: synced from Authentik on a schedule (every 15 minutes by
  default) or on demand. Members can be searched and filtered. You can also add
  manual entries for people without an xHain account.
- **Per-door access**: grant or revoke a member's access to each door
  ("key target") separately.
- **`authorized_keys` endpoints**: plain-text key lists with RSA signatures that
  the door controllers fetch.
- **Audit log**: every change to members, door access and doors is recorded,
  including who made it.
- **Notifications**: members get an email when the SSH key on their account
  changes.
- **Metrics**: a Prometheus endpoint at `/metrics`.

## Getting started

### Prerequisites

- Elixir 1.18 / Erlang/OTP 27+
- [sops](https://github.com/getsops/sops), [yq](https://github.com/mikefarah/yq)
  and [direnv](https://direnv.net) are optional. You only need them to load the
  encrypted `.env.yml` automatically.

### Environment

`config/runtime.exs` reads the following variables in **every** environment
(`dev` included), so they must be set before the app will boot:

| Variable | Purpose |
| --- | --- |
| `XHAIN_ACCOUNT_BASE_URL` | OIDC issuer of the xHain account system |
| `XHAIN_ACCOUNT_CLIENT_ID` | OIDC client ID |
| `XHAIN_ACCOUNT_CLIENT_SECRET` | OIDC client secret |
| `XHAIN_ACCOUNT_REDIRECT_URI` | OIDC callback URL (under `/auth`) registered with the account system |
| `AUTHENTIK_URL` | Base URL of the Authentik API (used by the member sync) |
| `AUTHENTIK_TOKEN` | Authentik API token |
| `AUTHENTIK_MEMBER_GROUP_UUID` | Group whose members count as active |
| `AUTHENTIK_ADMIN_GROUP` | *(optional)* OIDC group name that grants admin rights |
| `XDOOR_SIGNING_KEY` | PEM RSA private key used to sign `authorized_keys` |

If you have access to the sops key, `direnv allow` decrypts `.env.yml` and
exports all of these (see `.envrc`).

Production needs these as well:

| Variable | Purpose |
| --- | --- |
| `DATABASE_PATH` | Path to the SQLite database file |
| `SECRET_KEY_BASE` | Phoenix secret (`mix phx.gen.secret`) |
| `TOKEN_SIGNING_SECRET` | Secret for signing auth tokens |
| `PHX_HOST` | Public hostname |
| `PORT` | HTTP port (default `4000`) |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD` | Outgoing mail |
| `SYNC_INTERVAL_MINUTES` | *(optional)* Authentik sync interval (default `15`) |
| `POOL_SIZE` | *(optional)* DB pool size (default `10`) |

### Running locally

```sh
mix setup            # deps, database, seeds, assets
iex -S mix phx.server
```

Then open <http://localhost:4000>.

In development:

- The scheduled Authentik sync is **disabled**. Use the sync button in the UI
  instead.
- Emails are written to the log rather than sent.
- AshAdmin is at `/admin`, the LiveDashboard at `/dev/dashboard`, and the mailbox
  preview at `/dev/mailbox`.

### Working with production data

The `Makefile` has targets that copy the production database to your machine and
anonymize it:

```sh
make download_prod_data        # fetch prod DB (briefly stops prod) and obfuscate emails
make setup_dev_data_from_prod  # replace the dev DB with the obfuscated copy and migrate
make smoke_test_keys           # compare local /authorized_keys output with production
```

These targets need SSH access to the production host.

### Local observability stack

`dev/observability` contains a Docker Compose setup with Alloy, Prometheus and
Grafana. It scrapes the `/metrics` endpoint of a locally running server:

```sh
docker compose -f dev/observability/docker-compose.yml up
```

Grafana then runs at <http://localhost:3000>.

## Testing

```sh
mix test
mix precommit   # compile with warnings as errors, unlock unused deps, format, test
```

Run `mix precommit` before pushing. CI runs the tests and a Docker build for
every pull request.

## Deployment

Each push to `main` and each `v*.*.*` tag publishes a Docker image to
`ghcr.io/xhain-hackspace/valkyrie`. Tagged releases are also published as
`stable`. The container runs the Mix release (`/app/bin/server`) and applies
pending migrations on startup.

See `docker-compose.yml` for a minimal example of running the image.

### Adding a door in production

Doors are managed on the admin-only `/doors` page, which requires the
`AUTHENTIK_ADMIN_GROUP` group. When you create a door, you can grant it to every
existing keyholder at the same time. A door's slug can't be changed later
because it's part of the URL (`/authorized_keys/<slug>`).
