## Unit tests for buildRecoveryTicketContent.

import
  std/[strutils, unittest],
  scriptorium/recovery

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
