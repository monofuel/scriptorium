## Unit tests for ticket assignment validation.

import
  std/[os, osproc, tempfiles, unittest],
  scriptorium/[shared_state, ticket_assignment],
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
