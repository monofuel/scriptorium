# Dependency Visibility In Status Command

**Area:** status-worktrees
**Depends:** 0058

## Problem

V7 §29 requires that `scriptorium status` reports tickets blocked by circular dependencies and tickets waiting on unsatisfied dependencies. Currently, the status command has no dependency awareness.

## Requirements

### Circular dependency reporting
- When tickets are blocked by circular dependencies, status must report: `Blocked: <id> (circular dependency with <id-list>)`.
- Use the cycle detection logic from ticket 0058.

### Unsatisfied dependency reporting
- When tickets are blocked by unsatisfied (but non-circular) dependencies, status must report: `Waiting: <id> (depends on <id-list>)`.
- Show only open tickets whose dependencies are not yet in `tickets/done/`.

### Integration with readOrchestratorStatus
- Extend `OrchestratorStatus` to include blocked and waiting ticket information.
- Parse dependency fields from open tickets on the plan branch.
- Run cycle detection on the dependency graph.

## Acceptance Criteria

- `scriptorium status` shows `Blocked:` lines for circular dependency tickets.
- Shows `Waiting:` lines for tickets with unsatisfied dependencies.
- Uses cycle detection from ticket 0058.
- Existing status output unchanged.
- `make test` passes with tests covering both blocked and waiting output.

**Worktree:** /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0062-status-dependency-visibility

## Prediction
- predicted_difficulty: medium
- predicted_duration_minutes: 18
- reasoning: Multi-file integration wiring existing cycle detection into the status command with new OrchestratorStatus fields, dependency parsing, and formatted output — moderate complexity but building on established patterns from ticket 0058.

## Agent Run
- Model: claude-opus-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0062-status-dependency-visibility/.scriptorium/logs/0062/attempt-01.jsonl\n- Last Message File: /tmp/scriptorium/workspace-304b40cf6073a3f1/worktrees/tickets/0062-status-dependency-visibility/.scriptorium/logs/0062/attempt-01.last_message.txt\n
### Agent Last Message
```text
PR submitted successfully. Here's a summary of what was done:

**Changes across 5 files:**

1. **`src/scriptorium/shared_state.nim`** — Added `BlockedTicket` and `WaitingTicket` types, and added `blockedTickets`/`waitingTickets` fields to `OrchestratorStatus`.

2. **`src/scriptorium/ticket_assignment.nim`** — Extended `readOrchestratorStatus` to build the dependency graph via `buildDependencyGraph`, run `detectCycles`, collect cycle-blocked tickets, and identify tickets with unsatisfied (non-circular) dependencies.

3. **`src/scriptorium.nim`** — Added `Blocked:` and `Waiting:` output lines to `cmdStatus`.

4. **`tests/test_scriptorium.nim`** — Added 4 unit tests covering: circular dependency blocking, unsatisfied dependency waiting, satisfied dependencies (no output), and no-dependency tickets.

5. **`tests/integration_cli.nim`** — Added 2 integration tests verifying the CLI output format for blocked and waiting tickets.
```

### Agent Stdout Tail
```text
dependencies (no output), and no-dependency tickets.\n\n5. **`tests/integration_cli.nim`** — Added 2 integration tests verifying the CLI output format for blocked and waiting tickets.","stop_reason":"end_turn","session_id":"c80a76f9-ff5d-4a15-aa92-dc84ee2d792c","total_cost_usd":1.64984365,"usage":{"input_tokens":38,"cache_creation_input_tokens":52688,"cache_read_input_tokens":1745707,"output_tokens":10079,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":52688,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-opus-4-6":{"inputTokens":38,"outputTokens":10079,"cacheReadInputTokens":1745707,"cacheCreationInputTokens":52688,"webSearchRequests":0,"costUSD":1.4543184999999996,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":46,"outputTokens":6762,"cacheReadInputTokens":738379,"cacheCreationInputTokens":70265,"webSearchRequests":0,"costUSD":0.19552514999999998,"contextWindow":200000,"maxOutputTokens":32000}},"permission_denials":[],"fast_mode_state":"off","uuid":"43f2625f-224f-47d6-8bb5-c5065bc34450"}
```

## Review
**Review:** changes requested
- Model: claude-opus-4-6
- Backend: claude-code
- Exit Code: 0
- Wall Time: 4m44s

**Review Feedback:** Bug: Only the first node of each cycle is reported as blocked. All nodes in a cycle should be reported.

In `ticket_assignment.nim`, the blocked ticket loop iterates over `cycles` and only creates a `BlockedTicket` for `cycle[0]`:

```nim
for cycle in cycles:
  let ticketId = cycle[0]
  ...
  result.blockedTickets.add(BlockedTicket(ticketId: ticketId, ...))
```

`detectCycles` returns each cycle once (e.g. [A, B, A] for a mutual dependency). Since only `cycle[0]` gets a `BlockedTicket`, the other participants (e.g. B) are added to `cycleTicketIds` (so they are excluded from `waitingTickets`) but never added to `blockedTickets`. They silently disappear from status output.

Fix: iterate over all unique members of each cycle (indices 0 to len-2) and create a `BlockedTicket` for each one. For example:

```nim
var reportedCycleTickets = initHashSet[string]()
for cycle in cycles:
  let members = cycle[0 ..< cycle.len - 1]
  for member in members:
    if member in reportedCycleTickets:
      continue
    reportedCycleTickets.incl(member)
    var others: seq[string]
    for other in members:
      if other != member:
        others.add(other)
    result.blockedTickets.add(BlockedTicket(ticketId: member, cycleIds: others))
```

Also strengthen the test to verify ALL cycle participants are reported:
```nim
check status.blockedTickets.len == 2  # not >= 1
# Verify both 0010 and 0011 are blocked
```
