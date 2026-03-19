#!/usr/bin/env bash
# Sync nimby deps in workspace so nim.cfg paths resolve inside the container.

echo "=== Scriptorium Container Versions ==="
echo "Base image: monolab-nim:latest"
echo "Codex: $(codex --version 2>/dev/null || echo 'not found')"
echo "Claude Code: $(claude --version 2>/dev/null || echo 'not found')"
echo "======================================="

if [ -f /workspace/nimby.lock ]; then
  cd /workspace && nimby sync -g nimby.lock >/dev/null 2>&1
fi
exec /app/scriptorium "$@"
