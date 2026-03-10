#!/usr/bin/env bash
# Run scriptorium plan (interactive or one-shot).
# Usage: ./scripts/plan.sh [/path/to/target/repo] [prompt...]
#   Interactive: ./scripts/plan.sh /path/to/repo
#   One-shot:    ./scripts/plan.sh /path/to/repo "add a REST API endpoint"

set -euo pipefail
cd "$(dirname "$0")/.."

export SCRIPTORIUM_REPO="${1:-./workspace}"

if [ ! -d "$SCRIPTORIUM_REPO/.git" ]; then
  echo "error: $SCRIPTORIUM_REPO is not a git repository"
  echo "usage: $0 /path/to/target/repo [prompt...]"
  exit 1
fi

shift || true
if [ $# -gt 0 ]; then
  docker compose run --rm scriptorium plan "$@"
else
  docker compose run --rm -it scriptorium plan
fi
