## Unit tests for recovery module.

import
  std/[strutils, unittest],
  helpers,
  scriptorium/[notifications, recovery]

suite "buildRecoveryTicketContent":
  test "contains expected title":
    let result = buildRecoveryTicketContent("some failure", "abc1234")
    check "# Recovery: Fix Failing Tests on Main Branch" in result

  test "contains area recovery":
    let result = buildRecoveryTicketContent("some failure", "abc1234")
    check "**Area:** recovery" in result

  test "contains commit hash in description":
    let result = buildRecoveryTicketContent("some failure", "abc1234")
    check "abc1234" in result

  test "includes test output in fenced code block":
    let result = buildRecoveryTicketContent("FAIL: test_foo", "abc1234")
    check "## Test Failure Output" in result
    check "```\nFAIL: test_foo\n```" in result

  test "truncates output longer than MaxRecoveryTestOutputChars":
    let longOutput = 'X'.repeat(MaxRecoveryTestOutputChars + 500)
    let result = buildRecoveryTicketContent(longOutput, "abc1234")
    check "(output truncated)" in result
    check longOutput notin result

  test "does not truncate output exactly at MaxRecoveryTestOutputChars":
    let exactOutput = 'X'.repeat(MaxRecoveryTestOutputChars)
    let result = buildRecoveryTicketContent(exactOutput, "abc1234")
    check "(output truncated)" notin result
    check exactOutput in result

  test "empty test output produces fallback message":
    let result = buildRecoveryTicketContent("", "abc1234")
    check "Run `make test` and `make integration-test`" in result
    check "```" notin result

suite "hasStuckRecoveryTicket":
  test "returns false when no stuck tickets exist":
    withInitializedTempRepo("test_no_stuck_", proc(repoPath: string) =
      check not hasStuckRecoveryTicket(repoPath, PlanCallerCli)
    )

  test "returns true when a stuck recovery ticket exists":
    withInitializedTempRepo("test_stuck_recovery_", proc(repoPath: string) =
      let content = buildRecoveryTicketContent("FAIL", "abc1234")
      addTicketToPlan(repoPath, "stuck", "0042-recovery-abc1234.md", content)
      check hasStuckRecoveryTicket(repoPath, PlanCallerCli)
    )

  test "returns false when stuck ticket is not a recovery ticket":
    withInitializedTempRepo("test_stuck_nonrecov_", proc(repoPath: string) =
      let content = "# Fix bug\n\n**Area:** frontend\n"
      addTicketToPlan(repoPath, "stuck", "0042-fix-bug.md", content)
      check not hasStuckRecoveryTicket(repoPath, PlanCallerCli)
    )

suite "unhealthy-master notification on recovery ticket parking":
  test "unhealthy-master notification posted when recovery ticket is parked":
    withInitializedTempRepo("test_unhealthy_notif_", proc(repoPath: string) =
      clearNotifications(repoPath)
      let ticketContent = buildRecoveryTicketContent("FAIL", "abc1234")
      let area = parseAreaFromTicketContent(ticketContent)
      check area == "recovery"
      # Simulate what merge_queue does: post unhealthy-master for recovery tickets.
      if area == "recovery":
        postNotification(repoPath, "unhealthy-master", "Recovery ticket 0042 exhausted all attempts. Master remains unhealthy. Manual intervention required.")
      let messages = consumeNotifications(repoPath)
      check messages.len == 1
      check "unhealthy-master" notin messages[0]
      check "exhausted all attempts" in messages[0]
      check "Manual intervention required" in messages[0]
    )

  test "stuck notification posted for non-recovery tickets":
    withInitializedTempRepo("test_stuck_notif_", proc(repoPath: string) =
      clearNotifications(repoPath)
      let ticketContent = "# Fix bug\n\n**Area:** frontend\n"
      let area = parseAreaFromTicketContent(ticketContent)
      check area == "frontend"
      # Non-recovery tickets get the generic stuck notification.
      if area != "recovery":
        postNotification(repoPath, "stuck", "Ticket 0043 is stuck.")
      let messages = consumeNotifications(repoPath)
      check messages.len == 1
      check "stuck" in messages[0]
    )
