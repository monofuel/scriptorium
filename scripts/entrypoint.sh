#!/usr/bin/env bash
# Sync nimby deps in workspace so nim.cfg paths resolve inside the container.
if [ -f /workspace/nimby.lock ]; then
  cd /workspace && nimby sync -g nimby.lock >/dev/null 2>&1
fi
exec /app/scriptorium "$@"
