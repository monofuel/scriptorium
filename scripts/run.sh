#!/usr/bin/env bash
# Start the scriptorium orchestrator daemon in a container.

set -euo pipefail
cd "$(dirname "$0")/.."

docker compose run --rm scriptorium run
