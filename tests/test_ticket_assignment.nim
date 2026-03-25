## Unit tests for ticket state transition validation including stuck state.

import
  std/[os, osproc, unittest],
  scriptorium/ticket_assignment,
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
