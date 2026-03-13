# SIGSEGV Shutdown Fix For MCP Server Thread

**Area:** orchestrator

## Problem

The orchestrator calls `httpServer.close()` from the main thread while mummy's `serve()` is running on the server thread (see `orchestrator.nim` line ~3568). This causes a use-after-free that can trigger SIGSEGV in mummy's allocator during shutdown (V7 §28).

## Requirements

### Coordinated shutdown
- Replace the current `httpServer.close()` call from the main thread with a flag-based shutdown coordination.
- Main thread sets a shutdown flag (atomic bool or shared-memory signal).
- Server thread checks the shutdown flag periodically and calls `close()` on itself when the flag is set.
- Main thread calls `joinThread()` only after the server thread has exited.
- No sleep-based workarounds — shutdown must be event-driven.

### Investigation
- Check if mummy supports a flag-based or callback-based shutdown mechanism.
- If mummy does not support cooperative shutdown, investigate:
  - Newer mummy versions with shutdown support.
  - Alternative HTTP server libraries compatible with Nim's threading model.
  - A thin wrapper that polls a shutdown flag between request handling.

### Constraints
- The fix must not introduce sleep loops or polling delays during normal operation.
- All existing tests must pass.
- The server must still start and respond to MCP requests as before.

## Acceptance Criteria

- Orchestrator shuts down cleanly without SIGSEGV.
- Server thread closes itself rather than being closed cross-thread.
- `joinThread` only called after server thread exits.
- `make test` passes.
- Manual verification: `scriptorium run` followed by SIGINT/SIGTERM exits cleanly.
