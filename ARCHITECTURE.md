# Architecture

This document gives a high-level map of Valkyrie: what the parts are, where they
live and how data moves between them. For setup and day-to-day usage, see the
[README](README.md).

## Overview

```
                    ┌──────────────────────────┐
                    │  Authentik (xHain acct.) │
                    └─────┬──────────────┬─────┘
             REST API     │              │  OIDC login
         (member sync)    │              │  (admins/keyholders
                          ▼              ▼   managing access)
┌──────────────────────────────────────────────────────────────┐
│ Valkyrie                                                     │
│                                                              │
│  SyncScheduler ──► Members domain ◄── LiveViews (/members,   │
│                    (Ash + SQLite)     /members/audit, /doors)│
│                          │                                   │
│                          ▼                                   │
│              AuthorizedKeysController                        │
│              /authorized_keys[/<door>][.sig]                 │
└──────────────────────────┬───────────────────────────────────┘
                           │  HTTP pull (x-door header)
                           ▼
                    ┌─────────────┐
                    │ xDoor units │  verify signature, then accept
                    └─────────────┘  SSH keys in the list
```

Valkyrie is the source of truth for **who may open which door**. Authentik
owns member identities and their SSH keys. Valkyrie stores the per-door access
grants on top of that data. The door controllers never talk to Authentik: they
only fetch the signed key lists from Valkyrie.

## Tech stack

- **Phoenix 1.8 / LiveView 1.1**: web layer, served by Bandit.
- **Ash 3**: resources, actions and domains for all business data.
  - `ash_sqlite` stores the data in a single SQLite file.
  - `ash_authentication` provides OIDC login against the xHain account system.
  - `ash_paper_trail` keeps a version history (the audit log).
  - `ash_archival` soft-deletes members.
  - `ash_admin` provides a generic admin UI (dev only).
- **Req** calls the Authentik REST API.
- **Swoosh + Mua** send notification emails over SMTP.
- **telemetry_metrics_prometheus_core** exposes Prometheus metrics.
- **Tailwind v4 + esbuild** build the assets. The UI components in
  `lib/valkyrie_web/components` were generated with Mishka Chelekom.

## Code map

```
lib/
├── valkyrie/                  # business logic (no web code)
│   ├── application.ex         # supervision tree
│   ├── accounts/              # Accounts domain: User, Token (login)
│   ├── members.ex             # Members domain + Authentik sync logic
│   ├── members/               # Member, KeyTarget, KeyTargetAccess, sync, stats, mails
│   ├── versions/              # read-only view over all audit-log tables
│   ├── authentik.ex           # Authentik REST client
│   ├── secrets.ex             # feeds runtime secrets to AshAuthentication
│   └── release.ex             # migration helpers for the Mix release
└── valkyrie_web/
    ├── router.ex              # routes + auth/admin live_sessions
    ├── live_user_auth.ex      # on_mount hooks (user required / admin required)
    ├── live/                  # MemberLive, KeyTargetLive, AuditLive
    ├── controllers/           # AuthorizedKeysController, AuthController
    ├── plugs/                 # Prometheus scrape endpoint
    ├── telemetry.ex           # metric definitions + periodic measurements
    └── components/            # layouts + UI component library
```

## Domains and resources

### `Valkyrie.Accounts`

- **`User`** is a person who has logged into the web UI through OIDC. Users are
  created or updated (upserted) on every login. `is_admin` is set from the OIDC
  `groups` claim: it is `true` only when the claim contains
  `AUTHENTIK_ADMIN_GROUP`. If that setting is missing, nobody is an admin.
- **`Token`** holds the AshAuthentication session tokens.
- The seeds create a system user named **`authentik`**. Changes made by the
  member sync are recorded under this user, so the audit log shows them as
  coming from Authentik and not from a human.

### `Valkyrie.Members`

- **`Member`** is a person who may appear in an `authorized_keys` list. Members
  come from two sources:
  - **Synced** members mirror an Authentik user: username, SSH key, tree name,
    Matrix contact, email and active flag. `is_active` is true when the user is
    in `AUTHENTIK_MEMBER_GROUP_UUID`.
  - **Manual entries** (`is_manual_entry: true`) are created in the UI for
    people without an xHain account. The sync never touches them.

  Members are *soft-deleted* through `ash_archival`, so their history stays in
  the audit log. `username` is unique only among members that aren't archived,
  which allows a deleted member to be re-created.
- **`KeyTarget`** is a door (or room) with its own key list. Its `slug` must
  match `[a-z0-9-]`, can't be changed after creation, and appears in the URL
  `/authorized_keys/<slug>`. Doors are hard-deleted.
- **`KeyTargetAccess`** is the join table between `Member` and `KeyTarget`. A row
  means that the member has access to that door. Deleting a member or a door
  removes its rows through `ON DELETE CASCADE` in the database. Access is granted
  with the `change_keyholder_status` action. A member counts as a *keyholder* when
  they have access to at least one door.
- **`LastAccess`** is an in-memory resource stored in ETS. It records when a door
  last fetched its key list. Every update is broadcast over PubSub so the UI can
  show whether a door has picked up a change.

### `Valkyrie.Versions`

- **`CombinedVersion`** is a read-only resource backed by the SQL view
  `combined_versions`. The view is defined by hand in a migration, not generated
  from a resource. It merges the paper-trail tables of `Member`,
  `KeyTargetAccess` and `KeyTarget` into one table, which the audit log
  (`/members/audit`) filters and paginates.

## Key flows

### Member sync (Authentik → Valkyrie)

1. `Members.SyncScheduler` is a GenServer that starts a sync every
   `SYNC_INTERVAL_MINUTES`. The first sync runs 30 seconds after boot. Users can
   also start a sync from the members page. The scheduler is disabled in dev.
2. `Members.SyncState` makes sure only one sync runs at a time.
3. `Authentik.get_all_users/1` fetches every active user, 100 per page. After
   each page it broadcasts the progress on the `sync_members:progress` PubSub
   topic so the UI can display it live.
4. `Members.do_perform_sync/0` then processes the users:
   - It skips users without a username, account ID or tree name.
   - It archives synced members that no longer exist in Authentik. Manual
     entries are left alone.
   - It creates new members with the `:create` action, which is an upsert and
     restores archived members.
   - It updates changed members with `:sync_update`, recorded as the
     `authentik` actor.
   - When a member's SSH key has changed, it sends them an email through
     `Members.Notifications`.
5. The whole sync is wrapped in a `:telemetry.span` so its duration and failures
   are recorded as metrics.

The sync never changes door access. `:create` and `:sync_update` deliberately
leave the `key_targets` relationship alone, because otherwise every sync would
remove everyone's access.

### Serving keys (Valkyrie → xDoor)

`AuthorizedKeysController` serves these routes without authentication:

| Route | Content |
| --- | --- |
| `GET /authorized_keys` | Every keyholder, with duplicates removed |
| `GET /authorized_keys.sig` | Signature of the above |
| `GET /authorized_keys/<slug>` | Keyholders of one door |
| `GET /authorized_keys/<slug>.sig` | Signature of that list |

A member appears in a list only if they are active, have been granted the door
(for the combined list: any door), and have an SSH key that
`:ssh_file.decode/2` can parse. Each line has the form
`<type> <key> <tree_name>`, and lines are sorted by tree name so the output is
stable. The signature is an RSA signature over the exact response body, made
with `XDOOR_SIGNING_KEY` and base64-encoded.

When a request includes an `x-door` header, the controller updates `LastAccess`
for that list.

### Authentication and authorization

- Every browser route requires a logged-in user. The `/doors` routes also
  require `is_admin`. Both checks happen in the `on_mount` hooks in
  `ValkyrieWeb.LiveUserAuth`.
- Setting the compile-time flag `config :valkyrie, :disable_auth, true` turns
  these checks off, for local debugging only.
- `/authorized_keys*` and `/metrics` are public.

### Audit log

Paper trail records versions with `change_tracking_mode :full_diff` and stores
the name of the action. Each version links to the `User` who made the change
(`belongs_to_actor :user`), so callers must pass `actor:` when they want a
change attributed to someone. What gets recorded:

- `Member`: manual create/update, sync updates, and destroy. The plain `:create`
  that the sync uses is **not** recorded.
- `KeyTargetAccess`: every grant and revocation.
- `KeyTarget`: create, rename and delete.

Resources that are hard-deleted (`KeyTarget`, `KeyTargetAccess`) set
`reference_source? false`. This way their version rows don't hold a foreign key
to a source row that has been deleted.

## Runtime

The supervision tree in `Valkyrie.Application` starts these processes in order:

```
Telemetry ─ Repo ─ Ecto.Migrator ─ DNSCluster ─ PubSub
  ─ Members.SyncState ─ Members.SyncScheduler ─ Endpoint ─ AshAuthentication.Supervisor
```

- `Ecto.Migrator` runs migrations on boot, but only inside a release (when
  `RELEASE_NAME` is set). Locally, run `mix ash.migrate` yourself.
- `Valkyrie.version/0` returns the application version. `mix.exs` derives it
  at compile time from `git describe` (or from the `APP_VERSION` env var in
  Docker builds). The `Layouts.app` footer shows it.
- All data lives in one SQLite file. Back up that file, together with its `-wal`
  and `-shm` files, and the database is fully backed up.

## Observability

`ValkyrieWeb.Telemetry` defines the metrics that `/metrics` serves:

- Phoenix, Repo, VM and Swoosh metrics.
- Duration and exceptions of the member sync.
- Gauges for the total number of members and the number of keyholders, overall
  and per door. `Members.Stats` measures these every 10 seconds.

`dev/observability` contains a local Alloy → Prometheus → Grafana setup that
scrapes these metrics.

## Database migrations

Migrations are generated from the resource definitions with
`mix ash.codegen <name>`, which writes the files to `priv/repo/migrations` and
snapshots to `priv/resource_snapshots`. The `combined_versions` view is the one
exception: `CombinedVersion` sets `migrate? false`, and the view is defined by
hand in its own migration. When you change a paper-trail table, update that view
as well.
