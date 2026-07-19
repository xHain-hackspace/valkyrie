SHELL := /usr/bin/env bash

download_prod_data:
	./scripts/download_prod_db.sh ./data/valkyrie_prod.db
	./scripts/obfuscate_prod_db.sh ./data/valkyrie_prod.db ./data/valkyrie_obfuscated.db

migrate:
	mix ash.migrate

clean_dev_data:
	rm -f ./valkyrie_dev.db*

sync_prod_data:
	cp data/valkyrie_obfuscated.db ./valkyrie_dev.db

# Compare this codebase's /authorized_keys against production's.
# Run `make sync_prod_data` first to provide data/valkyrie_obfuscated.db.
smoke_test_keys: download_prod_data
	./scripts/smoke_test_authorized_keys.sh

setup_dev_data_from_prod: clean_dev_data sync_prod_data migrate

run_dev:
	MIX_ENV=dev iex -S mix phx.server

run_prod:
	DATABASE_PATH=./valkyrie_dev.db \
	MIX_ENV=prod SECRET_KEY_BASE=hhwWcYJ/Ya/dKG3eVrPUDKiqFnYs9fTmfWJGSCp0otJBbB4bbD1hNmNu1sQJcNye \
	TOKEN_SIGNING_SECRET=cVn/Be8CLY3BDXpic7VyGTakdAKj36peJAKyp+jvEJV01hWYTI4BIR5dcl3wFs6X \
	PHX_HOST=localhost \
	iex -S mix phx.server
