#!/usr/bin/env bash
#
# Obfuscate email addresses in a downloaded production database.
#
# Copies SRC to DEST and, in the copy, replaces every real email address with
# "<username>@x-hain.de" so the DB can be used locally (e.g. the /authorized_keys
# smoke test) without carrying personal email addresses around.
#
# Rewritten:
#   - members.email                 -> <username>@x-hain.de
#   - members_versions.changes JSON -> the email.{from,to,unchanged} values
#                                       (paper-trail history) get the same treatment,
#                                       using the username recorded in that same diff.
#
# Deliberately left untouched:
#   - members.ssh_public_key : returned verbatim by /authorized_keys — changing key
#                              comments would break the smoke-test comparison.
#   - members.matrix_contact : a Matrix handle (@user:x-hain.de), derived from the
#                              username, not a personal email address.
#
# The original SRC file is never modified.
#
# Usage: scripts/obfuscate_prod_db.sh [SRC] [DEST]
#   SRC   database to read  (default: <repo_root>/data/valkyrie_prod.db)
#   DEST  obfuscated copy to write (default: <repo_root>/data/valkyrie_obfuscated.db)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$REPO_ROOT/data"

SRC="${1:-$DATA_DIR/valkyrie_prod.db}"
DEST="${2:-$DATA_DIR/valkyrie_obfuscated.db}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; }

command -v sqlite3 >/dev/null || { err "sqlite3 not found in PATH"; exit 1; }
[[ -f "$SRC" ]] || { err "source DB '$SRC' not found"; exit 1; }

if [[ "$SRC" == "$DEST" ]]; then
  err "SRC and DEST must differ (the original is kept intact)"
  exit 1
fi

log "Copying $SRC -> $DEST ..."
mkdir -p "$(dirname "$DEST")"
cp "$SRC" "$DEST"

# Coalesce the username out of a paper-trail diff regardless of which envelope
# (unchanged / to / from) it landed in.
UNAME="COALESCE(json_extract(changes,'\$.username.unchanged'),json_extract(changes,'\$.username.to'),json_extract(changes,'\$.username.from'),'redacted')"

# For a given email path: replace only when the value is actually present and
# non-null (json_replace no-ops on absent paths; the CASE preserves present-null
# so we don't invent an email where the diff recorded none).
email_case() {
  local path="$1"
  printf "CASE WHEN json_extract(changes,'%s') IS NOT NULL THEN %s || '@x-hain.de' ELSE json_extract(changes,'%s') END" \
    "$path" "$UNAME" "$path"
}

log "Obfuscating emails in '$DEST' ..."
sqlite3 "$DEST" <<SQL
BEGIN;

UPDATE members
SET email = username || '@x-hain.de'
WHERE email IS NOT NULL AND email != '';

UPDATE members_versions
SET changes = json_replace(
  changes,
  '\$.email.from',      $(email_case '$.email.from'),
  '\$.email.to',        $(email_case '$.email.to'),
  '\$.email.unchanged', $(email_case '$.email.unchanged')
)
WHERE changes LIKE '%email%';

COMMIT;
SQL

# The copy inherits production's WAL journal mode, which leaves -wal/-shm sidecar
# files next to the DB. Switching to the rollback journal checkpoints the WAL into
# the main file; then drop any stale sidecars so the result is a single .db file.
log "Consolidating into a single DB file (dropping -wal/-shm) ..."
sqlite3 "$DEST" "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;" >/dev/null
rm -f "$DEST-wal" "$DEST-shm"

# Sanity check: no non-x-hain.de address should remain in the obfuscated columns.
leftover=$(sqlite3 "$DEST" "
  SELECT
    (SELECT count(*) FROM members
       WHERE email LIKE '%@%' AND email NOT LIKE '%@x-hain.de')
  + (SELECT count(*) FROM members_versions
       WHERE json_extract(changes,'\$.email.to')        LIKE '%@%' AND json_extract(changes,'\$.email.to')        NOT LIKE '%@x-hain.de')
  + (SELECT count(*) FROM members_versions
       WHERE json_extract(changes,'\$.email.from')       LIKE '%@%' AND json_extract(changes,'\$.email.from')       NOT LIKE '%@x-hain.de')
  + (SELECT count(*) FROM members_versions
       WHERE json_extract(changes,'\$.email.unchanged')  LIKE '%@%' AND json_extract(changes,'\$.email.unchanged')  NOT LIKE '%@x-hain.de');
")

if [[ "$leftover" -ne 0 ]]; then
  err "$leftover email value(s) not obfuscated — check the schema for new email columns."
  exit 1
fi

log "Done. Obfuscated DB written to $DEST"
