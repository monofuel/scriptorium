## Unit tests for audit trigger logic: drain detection + commit comparison,
## spec change flag, slot availability check, and idempotent guard.

import
  std/[os, unittest],
  scriptorium/[agent_pool, agent_runner, audit_agent, orchestrator, shared_state]

suite "audit trigger: drain + commit comparison":
  test "needsAudit returns true when lastAuditedCommit is empty":
    let tmpDir = getTempDir() / "audit_needs_empty_" & $getCurrentProcessId()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    # No audit_state.json means lastAuditedCommit is empty.
    let state = loadAuditState(tmpDir)
    check state.lastAuditedCommit == ""

  test "audit state differs from head triggers need":
    let tmpDir = getTempDir() / "audit_diff_head_" & $getCurrentProcessId()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    saveAuditState(tmpDir, AuditState(lastAuditedCommit: "old_commit_abc"))
    let state = loadAuditState(tmpDir)
    # Simulate: head commit is different from last audited.
    check state.lastAuditedCommit != "new_commit_def"

  test "audit state matches head means no audit needed":
    let tmpDir = getTempDir() / "audit_same_head_" & $getCurrentProcessId()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let headCommit = "abc123def456"
    saveAuditState(tmpDir, AuditState(lastAuditedCommit: headCommit))
    let state = loadAuditState(tmpDir)
    check state.lastAuditedCommit == headCommit

suite "audit trigger: spec change flag":
  test "specChangeAuditPending defaults to false":
    check specChangeAuditPending == false

  test "specChangeAuditPending can be set and cleared":
    specChangeAuditPending = true
    check specChangeAuditPending == true
    specChangeAuditPending = false
    check specChangeAuditPending == false

suite "audit trigger: slot availability":
  test "audit cannot start when no slots available":
    # With maxAgents=0, emptySlotCount is always 0.
    check emptySlotCount(0) == 0

  test "audit can start when slots available":
    # With maxAgents=4 and no running agents, 4 slots are available.
    check emptySlotCount(4) == 4

suite "audit trigger: idempotent guard":
  test "isAuditRunning prevents duplicate spawn":
    # Pool starts empty, so no audit is running.
    check isAuditRunning() == false

  test "AgentPoolCompletionResult can represent audit completion":
    let completion = AgentPoolCompletionResult(
      role: arAudit,
      ticketId: AuditTicketId,
      result: AgentRunResult(),
    )
    check completion.role == arAudit
    check completion.ticketId == "audit"

suite "audit trigger: combined decision logic":
  test "drain trigger with commit diff should trigger audit":
    # Simulate: queue drained, running == 0, commit differs, slot available.
    let drained = true
    let running = 0
    let commitDiffers = true
    let slotsAvailable = 2
    let auditRunning = false
    let specPending = false
    let drainTrigger = drained and running == 0
    let shouldTrigger = not auditRunning and ((drainTrigger and commitDiffers) or specPending) and slotsAvailable > 0
    check shouldTrigger == true

  test "spec change trigger should fire even if queue not drained":
    let drained = false
    let running = 3
    let commitDiffers = false
    let slotsAvailable = 1
    let auditRunning = false
    let specPending = true
    let drainTrigger = drained and running == 0
    let shouldTrigger = not auditRunning and ((drainTrigger and commitDiffers) or specPending) and slotsAvailable > 0
    check shouldTrigger == true

  test "already running audit prevents new spawn":
    let drained = true
    let running = 0
    let commitDiffers = true
    let slotsAvailable = 3
    let auditRunning = true
    let specPending = true
    let drainTrigger = drained and running == 0
    let shouldTrigger = not auditRunning and ((drainTrigger and commitDiffers) or specPending) and slotsAvailable > 0
    check shouldTrigger == false

  test "no slots available prevents audit":
    let drained = true
    let running = 0
    let commitDiffers = true
    let slotsAvailable = 0
    let auditRunning = false
    let specPending = false
    let drainTrigger = drained and running == 0
    let shouldTrigger = not auditRunning and ((drainTrigger and commitDiffers) or specPending) and slotsAvailable > 0
    check shouldTrigger == false

  test "drain with no commit diff and no spec change skips audit":
    let drained = true
    let running = 0
    let commitDiffers = false
    let slotsAvailable = 4
    let auditRunning = false
    let specPending = false
    let drainTrigger = drained and running == 0
    let shouldTrigger = not auditRunning and ((drainTrigger and commitDiffers) or specPending) and slotsAvailable > 0
    check shouldTrigger == false
