## Unit tests for ticket assignment validation.

import
  std/[os, osproc, tempfiles, unittest],
  scriptorium/[recovery, shared_state, ticket_assignment],
  helpers

suite "stuck state transition validation":
  test "stuck-parking commit passes validateTransitionCommitInvariant":
    let tmp = getTempDir() / "scriptorium_test_stuck_transition"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "in-progress", "0001-test.md", "# Ticket 1\n\n**Area:** a\n")

    withPlanWorktree(tmp, "stuck_transition", proc(planPath: string) =
      let fromPath = "tickets" / "in-progress" / "0001-test.md"
      let toPath = "tickets" / "stuck" / "0001-test.md"
      moveFile(planPath / fromPath, planPath / toPath)
      runCmdOrDie("git -C " & quoteShell(planPath) & " add -A tickets")
      runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m " &
        quoteShell("scriptorium: park stuck ticket 0001"))
    )

    validateTransitionCommitInvariant(tmp)

suite "ensureUniqueTicketStateInPlanPath":
  test "happy path: tickets in different state directories passes":
    let planPath = createTempDir("test_unique_", "", getTempDir())
    defer: removeDir(planPath)
    createDir(planPath / PlanTicketsOpenDir)
    createDir(planPath / PlanTicketsInProgressDir)
    createDir(planPath / PlanTicketsDoneDir)
    createDir(planPath / PlanTicketsStuckDir)
    writeFile(planPath / PlanTicketsOpenDir / "0001-alpha.md", "# Alpha\n")
    writeFile(planPath / PlanTicketsInProgressDir / "0002-beta.md", "# Beta\n")
    writeFile(planPath / PlanTicketsDoneDir / "0003-gamma.md", "# Gamma\n")

    ensureUniqueTicketStateInPlanPath(planPath)

  test "duplicate detection: same filename in open and in-progress raises":
    let planPath = createTempDir("test_unique_dup_", "", getTempDir())
    defer: removeDir(planPath)
    createDir(planPath / PlanTicketsOpenDir)
    createDir(planPath / PlanTicketsInProgressDir)
    createDir(planPath / PlanTicketsDoneDir)
    createDir(planPath / PlanTicketsStuckDir)
    writeFile(planPath / PlanTicketsOpenDir / "0001-dup.md", "# Dup\n")
    writeFile(planPath / PlanTicketsInProgressDir / "0001-dup.md", "# Dup\n")

    expect(ValueError):
      ensureUniqueTicketStateInPlanPath(planPath)

  test "stuck directory included: ticket in stuck and another state raises":
    let planPath = createTempDir("test_unique_stuck_", "", getTempDir())
    defer: removeDir(planPath)
    createDir(planPath / PlanTicketsOpenDir)
    createDir(planPath / PlanTicketsInProgressDir)
    createDir(planPath / PlanTicketsDoneDir)
    createDir(planPath / PlanTicketsStuckDir)
    writeFile(planPath / PlanTicketsStuckDir / "0005-stuck.md", "# Stuck\n")
    writeFile(planPath / PlanTicketsDoneDir / "0005-stuck.md", "# Stuck\n")

    expect(ValueError):
      ensureUniqueTicketStateInPlanPath(planPath)

  test "empty directories: no tickets passes validation":
    let planPath = createTempDir("test_unique_empty_", "", getTempDir())
    defer: removeDir(planPath)
    createDir(planPath / PlanTicketsOpenDir)
    createDir(planPath / PlanTicketsInProgressDir)
    createDir(planPath / PlanTicketsDoneDir)
    createDir(planPath / PlanTicketsStuckDir)

    ensureUniqueTicketStateInPlanPath(planPath)

suite "assignOldestOpenTicket areaFilter":
  test "areaFilter recovery assigns recovery ticket when mixed tickets exist":
    let tmp = getTempDir() / "scriptorium_test_area_filter_recovery"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-normal-bug.md", "# Normal Bug\n\n**Area:** orchestrator\n")
    addTicketToPlan(tmp, "open", "0002-recovery-fix.md", "# Recovery Fix\n\n**Area:** recovery\n")

    let assignment = assignOldestOpenTicket(tmp, PlanCallerCli, RecoveryAreaName)
    check assignment.inProgressTicket.len > 0
    let ticketId = ticketIdFromTicketPath(assignment.inProgressTicket)
    check ticketId == "0002"

  test "areaFilter recovery returns empty when only non-recovery tickets exist":
    let tmp = getTempDir() / "scriptorium_test_area_filter_no_recovery"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-normal-bug.md", "# Normal Bug\n\n**Area:** orchestrator\n")
    addTicketToPlan(tmp, "open", "0003-another-bug.md", "# Another Bug\n\n**Area:** merge-queue\n")

    let assignment = assignOldestOpenTicket(tmp, PlanCallerCli, RecoveryAreaName)
    check assignment.inProgressTicket.len == 0

  test "no areaFilter assigns oldest ticket regardless of area":
    let tmp = getTempDir() / "scriptorium_test_no_area_filter"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-normal-bug.md", "# Normal Bug\n\n**Area:** orchestrator\n")
    addTicketToPlan(tmp, "open", "0002-recovery-fix.md", "# Recovery Fix\n\n**Area:** recovery\n")

    let assignment = assignOldestOpenTicket(tmp, PlanCallerCli)
    check assignment.inProgressTicket.len > 0
    let ticketId = ticketIdFromTicketPath(assignment.inProgressTicket)
    check ticketId == "0001"
