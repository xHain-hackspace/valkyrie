#!/usr/bin/env bash
#
# Smoke test: does this codebase's /authorized_keys list match production's?
#
# Loads the obfuscated production database into the dev database, applies the
# current migrations, boots the dev server, and compares each list served
# locally against the one served by production at https://xdoor.x-hain.de.
#
# Always compares the combined list at /authorized_keys. Any positional
# arguments are treated as door slugs, each compared at /authorized_keys/<slug>.
#
#   pass  -> every compared list is byte-for-byte identical
#   fail  -> for each mismatch prints a unified diff, plus whether the *set* of
#            keys differs (membership changed) or only their order did
#
# Prerequisite: an obfuscated production DB at data/valkyrie_obfuscated.db.
# Produce it once (stops the prod container briefly) with:
#
#     make sync_prod_data
#
# Your existing dev database is backed up before the run and restored afterwards,
# so this test never clobbers your working data.
#
# Usage: scripts/smoke_test_authorized_keys.sh [-v|--verbose] [slug ...]
#
#   slug            door slug(s) to also compare at /authorized_keys/<slug>
#   -v, --verbose   show the raw stdout of the commands the script runs
#                   (migrations, dev server). By default their stdout is
#                   discarded; stderr is always shown.
#
# Examples:
#   scripts/smoke_test_authorized_keys.sh                 # combined list only
#   scripts/smoke_test_authorized_keys.sh main_door       # combined + main_door
#   scripts/smoke_test_authorized_keys.sh main_door lab -v
#
# Environment overrides:
#   OBF_DB     obfuscated prod DB to load     (default: data/valkyrie_obfuscated.db)
#   PROD_BASE  production base URL            (default: https://xdoor.x-hain.de)
#   PORT       local dev server port          (default: 4000)

set -euo pipefail

VERBOSE=0
SLUGS=()
for arg in "$@"; do
  case "$arg" in
    -v|--verbose) VERBOSE=1 ;;
    -*) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
    *)  SLUGS+=("$arg") ;;
  esac
done

# Where command stdout goes. Default: discarded. --verbose: the terminal.
# stderr is never redirected, so errors always surface.
OUT=/dev/null
[[ "$VERBOSE" -eq 1 ]] && OUT=/dev/stdout

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OBF_DB="${OBF_DB:-$REPO_ROOT/data/valkyrie_obfuscated.db}"
DEV_DB="${DEV_DB:-$REPO_ROOT/valkyrie_dev.db}"
PROD_BASE="${PROD_BASE:-https://xdoor.x-hain.de}"
PORT="${PORT:-4000}"
LOCAL_BASE="${LOCAL_BASE:-http://localhost:${PORT}}"

# Paths to compare: always the combined union list, then one per requested slug.
PATHS=("/authorized_keys")
for slug in "${SLUGS[@]:-}"; do
  [[ -n "$slug" ]] && PATHS+=("/authorized_keys/$slug")
done

WORK="$(mktemp -d)"
SERVER_LOG="$WORK/server.log"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32mPASS:\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*"; }

command -v curl >/dev/null || { err "curl not found in PATH"; exit 1; }
[[ -f "$OBF_DB" ]] || {
  err "obfuscated prod DB '$OBF_DB' not found."
  err "Run 'make sync_prod_data' first to download and obfuscate it."
  exit 1
}

SERVER_PID=""
TAIL_PID=""
DEV_DB_BACKED_UP=0

cleanup() {
  local rc=$?
  # Stop the verbose log streamer, if any.
  if [[ -n "$TAIL_PID" ]] && kill -0 "$TAIL_PID" 2>/dev/null; then
    kill "$TAIL_PID" 2>/dev/null || true
  fi
  # Stop the dev server (and its child beam) if we started one.
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    log "Stopping dev server (pid $SERVER_PID)..."
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  # Restore the original dev database.
  if [[ "$DEV_DB_BACKED_UP" -eq 1 ]]; then
    log "Restoring original dev database..."
    rm -f "$DEV_DB" "$DEV_DB-wal" "$DEV_DB-shm"
    [[ -f "$DEV_DB.smoke-bak" ]] && mv "$DEV_DB.smoke-bak" "$DEV_DB"
    [[ -f "$DEV_DB-wal.smoke-bak" ]] && mv "$DEV_DB-wal.smoke-bak" "$DEV_DB-wal"
    [[ -f "$DEV_DB-shm.smoke-bak" ]] && mv "$DEV_DB-shm.smoke-bak" "$DEV_DB-shm"
  fi
  rm -rf "$WORK"
  exit "$rc"
}
trap cleanup EXIT

# --- Load the obfuscated prod DB into the dev DB path -------------------------
log "Backing up existing dev database..."
DEV_DB_BACKED_UP=1
[[ -f "$DEV_DB" ]]     && mv "$DEV_DB" "$DEV_DB.smoke-bak"
[[ -f "$DEV_DB-wal" ]] && mv "$DEV_DB-wal" "$DEV_DB-wal.smoke-bak"
[[ -f "$DEV_DB-shm" ]] && mv "$DEV_DB-shm" "$DEV_DB-shm.smoke-bak"

log "Loading obfuscated prod DB into $DEV_DB ..."
cp "$OBF_DB" "$DEV_DB"
rm -f "$DEV_DB-wal" "$DEV_DB-shm"

# --- Apply current migrations to the prod data -------------------------------
log "Applying migrations (mix ash.migrate)..."
MIX_ENV=dev mix ash.migrate >"$OUT"

# --- Boot the dev server -----------------------------------------------------
log "Starting dev server on port $PORT ..."
MIX_ENV=dev PORT="$PORT" mix phx.server >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

# In verbose mode, mirror the server log to the terminal as it grows. Kept
# separate from the server process so $SERVER_PID stays the beam we must kill.
if [[ "$VERBOSE" -eq 1 ]]; then
  tail -f "$SERVER_LOG" &
  TAIL_PID=$!
fi

log "Waiting for server to become ready..."
ready=0
for _ in $(seq 1 60); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    err "Dev server exited early. Last log lines:"
    tail -n 30 "$SERVER_LOG" >&2
    exit 1
  fi
  if curl -fsS -o /dev/null "${LOCAL_BASE}/authorized_keys" 2>/dev/null; then
    ready=1
    break
  fi
  sleep 1
done
[[ "$ready" -eq 1 ]] || { err "Server did not become ready in time."; tail -n 30 "$SERVER_LOG" >&2; exit 1; }

# --- Compare one path locally vs. production ---------------------------------
# Returns 0 on identical lists, 1 on any difference (or fetch failure).
compare_one() {
  local path="$1"
  local local_out="$WORK/local.txt" prod_out="$WORK/prod.txt"

  echo
  log "Comparing $path"

  if ! curl -fsS "${LOCAL_BASE}${path}" -o "$local_out"; then
    fail "$path — could not fetch local (${LOCAL_BASE}${path})."
    return 1
  fi
  if ! curl -fsS "${PROD_BASE}${path}" -o "$prod_out"; then
    fail "$path — could not fetch prod (${PROD_BASE}${path})."
    return 1
  fi

  local local_n prod_n
  local_n=$(grep -c . "$local_out" || true)
  prod_n=$(grep -c . "$prod_out" || true)
  printf '\033[1m    entries — local: %s | prod: %s\033[0m\n' "$local_n" "$prod_n"

  if diff -q "$local_out" "$prod_out" >/dev/null; then
    ok "$path — byte-for-byte identical."
    return 0
  fi

  fail "$path — local differs from production."
  echo "--- unified diff (< local, > prod) -------------------------------------"
  diff -u "$local_out" "$prod_out" || true
  echo
  if diff -q <(sort "$local_out") <(sort "$prod_out") >/dev/null; then
    echo "Note: the SET of keys is identical — only the ORDER differs."
  else
    echo "--- set difference (sorted; < local-only, > prod-only) -----------------"
    diff <(sort "$local_out") <(sort "$prod_out") || true
  fi
  return 1
}

failures=0
for path in "${PATHS[@]}"; do
  compare_one "$path" || failures=$((failures + 1))
done

echo
if [[ "$failures" -eq 0 ]]; then
  ok "all ${#PATHS[@]} list(s) match production."
  exit 0
fi
fail "$failures of ${#PATHS[@]} list(s) differ from production."
exit 1
