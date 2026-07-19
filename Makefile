SHELL := /usr/bin/env bash

sync_prod_data:
	./scripts/download_prod_db.sh ./data/valkyrie_prod.db
	./scripts/obfuscate_prod_db.sh ./data/valkyrie_prod.db ./data/valkyrie_obfuscated.db

migrate:
	mix ash.migrate

# Compare this codebase's /authorized_keys against production's.
# Run `make sync_prod_data` first to provide data/valkyrie_obfuscated.db.
smoke_test_keys: sync_prod_data
	./scripts/smoke_test_authorized_keys.sh

run_dev:
	MIX_ENV=dev iex -S mix phx.server

run_prod:
	DATABASE_PATH=./valkyrie_dev.db \
	MIX_ENV=prod SECRET_KEY_BASE=hhwWcYJ/Ya/dKG3eVrPUDKiqFnYs9fTmfWJGSCp0otJBbB4bbD1hNmNu1sQJcNye \
	TOKEN_SIGNING_SECRET=cVn/Be8CLY3BDXpic7VyGTakdAKj36peJAKyp+jvEJV01hWYTI4BIR5dcl3wFs6X \
	PHX_HOST=localhost \
	iex -S mix phx.server
