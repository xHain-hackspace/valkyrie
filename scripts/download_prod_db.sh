#!/usr/bin/env bash
#
# Download the current production SQLite database.
#
# Stops the production container (so the DB file is at rest and not mid-write),
# copies valkyrie.db to a local destination, then restarts the container — even
# if the copy fails. Intended as the data source for the /authorized_keys smoke
# test that compares this implementation against production.
#
# Usage: scripts/download_prod_db.sh [DEST]
#   DEST  local path to write the DB to (default: <repo_root>/data/valkyrie_prod.db)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$REPO_ROOT/data"

SSH_HOST="${SSH_HOST:-oak}"
REMOTE_COMPOSE="${REMOTE_COMPOSE:-/media/ssd/docker_compose/valkyrie/docker-compose.yml}"
REMOTE_DB="${REMOTE_DB:-/media/ssd/valkyrie/database/valkyrie.db}"
DEST="${1:-$DATA_DIR/valkyrie_prod.db}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; }

compose_up() {
  log "Restarting production container..."
  if ! ssh "$SSH_HOST" docker compose -f "$REMOTE_COMPOSE" up -d; then
    err "Failed to restart the production container — restart it manually:"
    err "  ssh $SSH_HOST docker compose -f $REMOTE_COMPOSE up -d"
    return 1
  fi
}

# Whatever happens after the container is stopped, make sure we try to bring it
# back up. Preserve the original exit code so failures still surface.
container_down=0
cleanup() {
  local rc=$?
  if [[ "$container_down" -eq 1 ]]; then
    compose_up || rc=1
  fi
  exit "$rc"
}
trap cleanup EXIT

command -v ssh >/dev/null || { err "ssh not found in PATH"; exit 1; }
command -v scp >/dev/null || { err "scp not found in PATH"; exit 1; }

log "Checking SSH connectivity to '$SSH_HOST'..."
ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_HOST" true \
  || { err "Cannot reach '$SSH_HOST' over SSH."; exit 1; }

log "Stopping production container..."
container_down=1
ssh "$SSH_HOST" docker compose -f "$REMOTE_COMPOSE" down

log "Copying database from $SSH_HOST:$REMOTE_DB ..."
mkdir -p "$(dirname "$DEST")"
scp "$SSH_HOST:$REMOTE_DB" "$DEST"

# Copy done; container restart is handled by the EXIT trap.
log "Database written to $DEST"
