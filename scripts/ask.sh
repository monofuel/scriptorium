#!/usr/bin/env bash
# Start a read-only Q&A session with the Architect.

set -euo pipefail
cd "$(dirname "$0")/.."

docker compose run --rm -it scriptorium ask
