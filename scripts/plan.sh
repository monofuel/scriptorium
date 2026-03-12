#!/usr/bin/env bash
# Run scriptorium plan (interactive or one-shot).
# Usage: ./scripts/plan.sh [prompt...]
#   Interactive: ./scripts/plan.sh
#   One-shot:    ./scripts/plan.sh "add a REST API endpoint"

set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -gt 0 ]; then
  docker compose run --rm scriptorium plan "$@"
else
  docker compose run --rm -it scriptorium plan
fi
