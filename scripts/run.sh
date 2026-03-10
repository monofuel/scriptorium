#!/usr/bin/env bash
# Start the scriptorium orchestrator daemon in a container.
# Usage: ./scripts/run.sh [/path/to/target/repo]

set -euo pipefail
cd "$(dirname "$0")/.."

export SCRIPTORIUM_REPO="${1:-./workspace}"

if [ ! -d "$SCRIPTORIUM_REPO/.git" ]; then
  echo "error: $SCRIPTORIUM_REPO is not a git repository"
  echo "usage: $0 /path/to/target/repo"
  exit 1
fi

docker compose run --rm scriptorium run
