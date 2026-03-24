## Tests for ticket assignment, dependencies, and parallel assignment.

import
  std/[algorithm, json, locks, os, osproc, sequtils, sha1, strformat, strutils, tables, tempfiles, times, unittest],
  jsony,
  scriptorium/[agent_runner, config, init, logging, orchestrator, ticket_metadata],
  helpers

suite "orchestrator ticket assignment":
  test "oldest open ticket picks the lowest numeric ID":
    let tmp = getTempDir() / "scriptorium_test_oldest_open_ticket"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** b\n")
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let oldest = oldestOpenTicket(tmp)
    check oldest == "tickets/open/0001-first.md"

  test "assign moves ticket to in-progress in one commit":
    let tmp = getTempDir() / "scriptorium_test_assign_transition"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let before = planCommitCount(tmp)
    let assignment = assignOldestOpenTicket(tmp)
    let after = planCommitCount(tmp)
    let files = planTreeFiles(tmp)

    check assignment.openTicket == "tickets/open/0001-first.md"
    check assignment.inProgressTicket == "tickets/in-progress/0001-first.md"
    check "tickets/in-progress/0001-first.md" in files
    check "tickets/open/0001-first.md" notin files
    check after == before + 3

  test "assign creates worktree and writes worktree metadata":
    let tmp = getTempDir() / "scriptorium_test_assign_worktree"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    let normalizedWorktreePath = normalizedPathForTest(assignment.worktree)
    let normalizedManagedRoot = normalizedPathForTest(tmp / ".scriptorium")
    check assignment.worktree.len > 0
    check assignment.branch == "scriptorium/ticket-0001"
    check assignment.worktree in gitWorktreePaths(tmp)
    check normalizedWorktreePath.startsWith(normalizedManagedRoot & "/")

    let (ticketContent, rc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/in-progress/0001-first.md"
    )
    check rc == 0
    check ("**Worktree:** " & assignment.worktree) in ticketContent

  test "cleanup removes stale ticket worktrees":
    let tmp = getTempDir() / "scriptorium_test_cleanup_worktree"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    moveTicketStateInPlan(tmp, "in-progress", "done", "0001-first.md")

    let removed = cleanupStaleTicketWorktrees(tmp)
    check assignment.worktree in removed
    check assignment.worktree notin gitWorktreePaths(tmp)

suite "parallel ticket assignment":
  test "two tickets with different areas are both assigned when maxAgents >= 2":
    let tmp = getTempDir() / "scriptorium_test_parallel_diff_areas"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** area-b\n")

    let assignments = assignOpenTickets(tmp, 2)
    check assignments.len == 2
    check assignments[0].openTicket == "tickets/open/0001-first.md"
    check assignments[0].inProgressTicket == "tickets/in-progress/0001-first.md"
    check assignments[1].openTicket == "tickets/open/0002-second.md"
    check assignments[1].inProgressTicket == "tickets/in-progress/0002-second.md"
    check assignments[0].branch == "scriptorium/ticket-0001"
    check assignments[1].branch == "scriptorium/ticket-0002"
    check assignments[0].worktree.len > 0
    check assignments[1].worktree.len > 0

  test "two tickets with same area: only the oldest is assigned":
    let tmp = getTempDir() / "scriptorium_test_parallel_same_area"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** shared\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** shared\n")

    let assignments = assignOpenTickets(tmp, 2)
    check assignments.len == 1
    check assignments[0].openTicket == "tickets/open/0001-first.md"
    check assignments[0].inProgressTicket == "tickets/in-progress/0001-first.md"

  test "assignment respects maxAgents cap":
    let tmp = getTempDir() / "scriptorium_test_parallel_cap"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** area-b\n")
    addTicketToPlan(tmp, "open", "0003-third.md", "# Ticket 3\n\n**Area:** area-c\n")

    let assignments = assignOpenTickets(tmp, 2)
    check assignments.len == 2
    check assignments[0].openTicket == "tickets/open/0001-first.md"
    check assignments[1].openTicket == "tickets/open/0002-second.md"

  test "maxAgents = 1 assigns only one ticket":
    let tmp = getTempDir() / "scriptorium_test_parallel_single"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** area-b\n")

    let assignments = assignOpenTickets(tmp, 1)
    check assignments.len == 1
    check assignments[0].openTicket == "tickets/open/0001-first.md"
    check assignments[0].inProgressTicket == "tickets/in-progress/0001-first.md"
    check assignments[0].branch == "scriptorium/ticket-0001"

  test "assignOpenTickets skips area already in-progress":
    let tmp = getTempDir() / "scriptorium_test_parallel_skip_inprogress"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "in-progress", "0001-first.md", "# Ticket 1\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0003-third.md", "# Ticket 3\n\n**Area:** area-b\n")

    let assignments = assignOpenTickets(tmp, 3)
    check assignments.len == 1
    check assignments[0].openTicket == "tickets/open/0003-third.md"

  test "assignOpenTickets returns empty when no open tickets":
    let tmp = getTempDir() / "scriptorium_test_parallel_empty"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    let assignments = assignOpenTickets(tmp, 3)
    check assignments.len == 0

suite "ticket dependency parsing":
  test "parseDependsFromTicketContent with no depends returns empty":
    let content = "# Ticket\n\n**Area:** a\n"
    check parseDependsFromTicketContent(content).len == 0

  test "parseDependsFromTicketContent with single dependency":
    let content = "# Ticket\n\n**Area:** a\n**Depends:** 0045\n"
    check parseDependsFromTicketContent(content) == @["0045"]

  test "parseDependsFromTicketContent with multiple dependencies":
    let content = "# Ticket\n\n**Area:** a\n**Depends:** 0045, 0046\n"
    check parseDependsFromTicketContent(content) == @["0045", "0046"]

  test "parseDependsFromTicketContent with empty value returns empty":
    let content = "# Ticket\n\n**Area:** a\n**Depends:**\n"
    check parseDependsFromTicketContent(content).len == 0

  test "parseDependsFromTicketContent trims whitespace":
    let content = "# Ticket\n\n**Depends:**  0045 , 0046 \n"
    check parseDependsFromTicketContent(content) == @["0045", "0046"]

suite "ticket dependency assignment":
  test "assignOldestOpenTicket skips ticket with unsatisfied dependency":
    let tmp = getTempDir() / "scriptorium_test_dep_unsatisfied"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n**Depends:** 9999\n")

    let assignment = assignOldestOpenTicket(tmp)
    check assignment.inProgressTicket.len == 0

  test "assignOldestOpenTicket assigns ticket with satisfied dependency":
    let tmp = getTempDir() / "scriptorium_test_dep_satisfied"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "done", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** b\n**Depends:** 0001\n")

    let assignment = assignOldestOpenTicket(tmp)
    check assignment.inProgressTicket == "tickets/in-progress/0002-second.md"

  test "assignOldestOpenTicket skips blocked ticket and assigns next":
    let tmp = getTempDir() / "scriptorium_test_dep_skip_blocked"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n**Depends:** 9999\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** b\n")

    let assignment = assignOldestOpenTicket(tmp)
    check assignment.inProgressTicket == "tickets/in-progress/0002-second.md"

  test "assignOpenTickets skips ticket with unsatisfied dependency":
    let tmp = getTempDir() / "scriptorium_test_dep_parallel_skip"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** area-b\n**Depends:** 9999\n")

    let assignments = assignOpenTickets(tmp, 2)
    check assignments.len == 1
    check assignments[0].openTicket == "tickets/open/0001-first.md"

  test "assignOpenTickets assigns ticket after dependency is done":
    let tmp = getTempDir() / "scriptorium_test_dep_parallel_done"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "done", "0001-first.md", "# Ticket 1\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** area-b\n**Depends:** 0001\n")

    let assignments = assignOpenTickets(tmp, 2)
    check assignments.len == 1
    check assignments[0].openTicket == "tickets/open/0002-second.md"

suite "status dependency visibility":
  test "readOrchestratorStatus auto-repairs cycle and reports waiting deps":
    let tmp = getTempDir() / "scriptorium_test_status_cycle_repaired"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0010-alpha.md", "# Alpha\n\n**Area:** a\n**Depends:** 0011\n")
    addTicketToPlan(tmp, "open", "0011-beta.md", "# Beta\n\n**Area:** b\n**Depends:** 0010\n")

    let status = readOrchestratorStatus(tmp)
    # Cycles are auto-repaired: 0011 (newest) has edge to 0010 removed.
    # 0010 still depends on 0011 (unsatisfied) → reported as waiting.
    # 0011 has no deps after repair → not waiting.
    check status.blockedTickets.len == 0
    check status.waitingTickets.len == 1
    check status.waitingTickets[0].ticketId == "0010"

  test "readOrchestratorStatus reports tickets with unsatisfied deps as waiting":
    let tmp = getTempDir() / "scriptorium_test_status_waiting"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0020-first.md", "# First\n\n**Area:** a\n**Depends:** 9999\n")

    let status = readOrchestratorStatus(tmp)
    check status.waitingTickets.len == 1
    check status.waitingTickets[0].ticketId == "0020"
    check status.waitingTickets[0].dependsOn == @["9999"]

  test "readOrchestratorStatus does not report tickets with satisfied deps":
    let tmp = getTempDir() / "scriptorium_test_status_satisfied"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "done", "0030-prereq.md", "# Prereq\n\n**Area:** a\n")
    addTicketToPlan(tmp, "open", "0031-next.md", "# Next\n\n**Area:** b\n**Depends:** 0030\n")

    let status = readOrchestratorStatus(tmp)
    check status.blockedTickets.len == 0
    check status.waitingTickets.len == 0

  test "readOrchestratorStatus does not report tickets without dependencies":
    let tmp = getTempDir() / "scriptorium_test_status_no_deps"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0040-plain.md", "# Plain\n\n**Area:** a\n")

    let status = readOrchestratorStatus(tmp)
    check status.blockedTickets.len == 0
    check status.waitingTickets.len == 0

  test "readOrchestratorStatus auto-repairs three-node cycle":
    let tmp = getTempDir() / "scriptorium_test_status_cycle_three"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addTicketToPlan(tmp, "open", "0050-a.md", "# A\n\n**Area:** a\n**Depends:** 0051\n")
    addTicketToPlan(tmp, "open", "0051-b.md", "# B\n\n**Area:** b\n**Depends:** 0052\n")
    addTicketToPlan(tmp, "open", "0052-c.md", "# C\n\n**Area:** c\n**Depends:** 0050\n")

    let status = readOrchestratorStatus(tmp)
    # Cycle auto-repaired: 0052 (newest) has edge to 0050 removed.
    # 0050 waits on 0051, 0051 waits on 0052, 0052 is free.
    check status.blockedTickets.len == 0
    check status.waitingTickets.len == 2
