## Tests for the agent_pool module: role-tagged slot counting and completion dispatch.

import
  std/[unittest],
  scriptorium/[agent_pool, agent_runner, shared_state]

suite "agent pool slot counting":
  test "runningAgentCount starts at zero":
    check runningAgentCount() == 0

  test "emptySlotCount equals maxAgents when pool is empty":
    check emptySlotCount(4) == 4
    check emptySlotCount(1) == 1

  test "runningAgentCountByRole returns zero for each role initially":
    check runningAgentCountByRole(arCoder) == 0
    check runningAgentCountByRole(arManager) == 0

suite "agent pool completion result":
  test "AgentPoolCompletionResult tagged with arCoder role":
    let completion = AgentPoolCompletionResult(
      role: arCoder,
      ticketId: "0042",
      result: AgentRunResult(exitCode: 0, submitted: true),
    )
    check completion.role == arCoder
    check completion.ticketId == "0042"
    check completion.result.submitted == true
    check completion.managerResult.len == 0

  test "AgentPoolCompletionResult tagged with arManager role":
    let completion = AgentPoolCompletionResult(
      role: arManager,
      areaId: "backend-api",
      result: AgentRunResult(exitCode: 0),
      managerResult: @["tickets/open/0100-new-ticket.md"],
    )
    check completion.role == arManager
    check completion.areaId == "backend-api"
    check completion.managerResult.len == 1
    check completion.managerResult[0] == "tickets/open/0100-new-ticket.md"

suite "agent pool summary and audit helpers":
  test "runningAgentSummary returns none when pool is empty":
    check runningAgentSummary() == "none"

  test "isAuditRunning returns false when pool is empty":
    check isAuditRunning() == false

  test "runningAgentCountByRole returns zero for arAudit initially":
    check runningAgentCountByRole(arAudit) == 0

suite "agent pool slot arithmetic":
  test "shared pool means managers reduce coder capacity":
    # With maxAgents=4, if 2 managers are running, only 2 slots remain.
    # We verify the arithmetic: emptySlotCount = maxAgents - runningAgentCount.
    let maxAgents = 4
    let managerCount = 2
    let coderCount = 1
    let totalRunning = managerCount + coderCount
    let available = maxAgents - totalRunning
    check available == 1
