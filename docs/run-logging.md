# Improving `scriptorium run` Logging

## Problem

The orchestrator output during `scriptorium run` is hard to follow. Long periods of silence broken by terse summary lines make it difficult to tell what the system is doing at any given moment. The raw `DEBUG claude-code command:` lines dump full argv without context, and there is no indication of which area or ticket is being worked on during manager/architect phases.

## Entrypoint Noise

The nimby sync in `scripts/entrypoint.sh` prints version and timing info on every invocation:

```
Nimby 0.1.20
Using global packages directory.
Took: 0.02 seconds
```

Fix: redirect nimby stdout to `/dev/null` in the entrypoint. Errors should still go to stderr.

## Agent Lifecycle Logging

Add before/after log lines around every agent invocation. Each line should include the role and relevant context.

### Architect

Before:
```
[INFO] architect: generating areas from spec
```

After (success):
```
[INFO] architect: areas updated (11 areas)
```

### Manager

Before each area:
```
[INFO] manager: generating tickets for area stall-detection
```

After each area:
```
[INFO] manager: created 3 tickets for area stall-detection
```

Summary after all areas:
```
[INFO] manager: tickets created (8 total across 4 areas)
```

### Coding Agent

Before:
```
[INFO] coding agent: starting ticket 0003-stall-detection (attempt 1)
```

After:
```
[INFO] coding agent: completed ticket 0003 (exit 0, attempt 1)
```

Or on stall:
```
[INFO] coding agent: stalled on ticket 0003 (no submit_pr, attempt 1)
```

### Merge Queue

```
[INFO] merge queue: testing ticket 0003 on branch scriptorium/ticket-0003
[INFO] merge queue: make test passed
[INFO] merge queue: make integration-test passed
[INFO] merge queue: merged ticket 0003 to master
```

Or on failure:
```
[INFO] merge queue: make test failed for ticket 0003
[INFO] merge queue: reopened ticket 0003
```

## Raw Command Logging

Replace the current `DEBUG claude-code command: claude --print --output-format stream-json ...` with a compact version:

```
[DEBUG] running claude-opus-4-6 (architect) in /tmp/scriptorium/.../worktrees/plan
```

The full command is still useful for debugging but should only appear in the log file, not stdout. If stdout and the log file currently get identical content, split them: stdout gets INFO and above, the log file gets DEBUG and above.

## Agent Event Forwarding

The harness already parses stream events (heartbeat, reasoning, tool, status, message) and the orchestrator already wires up `onEvent` callbacks for coding agents. Extend this to architect and manager runs so the operator sees real-time activity:

```
[DEBUG] architect: tool write areas/stall-detection.md
[DEBUG] architect: tool write areas/log-forwarding.md
[DEBUG] manager[stall-detection]: tool write tickets/open/0003-stall-detection.md
[DEBUG] coding[0003]: tool edit src/scriptorium/orchestrator.nim
[DEBUG] coding[0003]: tool read src/scriptorium/harness_claude_code.nim
```

This overlaps with v2 spec section 10 (Coding Agent Log Forwarding). The v2 spec scopes it to coding agents only, but the same mechanism works for all roles. Consider expanding the scope.

## Log Level Separation

Currently stdout and the log file appear to get the same content. Separate them:

- **stdout**: INFO and above. This is the human-friendly view.
- **log file**: DEBUG and above. Full command lines, raw event details, timing.

The `SCRIPTORIUM_LOG_LEVEL` env var and config `logLevel` already exist. Make sure they control the log file level independently, or add a `stdoutLogLevel` config.

## Health Check Logging

The `master is unhealthy` message currently repeats every tick with no additional context. Improve:

- Log it once, then suppress until master becomes healthy again.
- On first unhealthy detection, include which quality gate failed:
  ```
  [WARN] master is unhealthy: make test failed (exit 2)
  ```
- When master recovers:
  ```
  [INFO] master is healthy again (commit abc1234)
  ```

## Idle Tick Logging

When the orchestrator is idle (no work to do), it currently logs nothing between ticks. Add a periodic heartbeat so operators know it's alive:

```
[DEBUG] tick: idle (0 open, 0 in-progress, 3 done)
```

This should appear at DEBUG level so it doesn't spam stdout by default.

## Summary of Changes

| Area | File(s) | Effort |
|------|---------|--------|
| Suppress nimby noise | `scripts/entrypoint.sh` | Small |
| Agent lifecycle log lines | `src/scriptorium/orchestrator.nim` | Small |
| Compact DEBUG command lines | `src/scriptorium/harness_claude_code.nim`, `harness_codex.nim` | Small |
| Log level split (stdout vs file) | `src/scriptorium/logging.nim` | Medium |
| Agent event forwarding for all roles | `src/scriptorium/orchestrator.nim` | Medium |
| Health check dedup and context | `src/scriptorium/orchestrator.nim` | Small |
| Idle tick heartbeat | `src/scriptorium/orchestrator.nim` | Small |
