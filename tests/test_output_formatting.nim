## Unit tests for formatAgentRunNote and appendAgentRunNote.

import
  std/[strutils, unittest],
  scriptorium/[agent_runner, config, output_formatting, prompt_builders]

proc makeResult(
  lastMessage = "",
  stdout = "",
  exitCode = 0,
  attempt = 1,
  attemptCount = 1,
): AgentRunResult =
  ## Build an AgentRunResult with sensible defaults for testing.
  result = AgentRunResult(
    backend: harnessClaudeCode,
    exitCode: exitCode,
    attempt: attempt,
    attemptCount: attemptCount,
    stdout: stdout,
    logFile: "/tmp/log.txt",
    lastMessageFile: "/tmp/last_msg.txt",
    lastMessage: lastMessage,
    timeoutKind: "none",
  )

suite "formatAgentRunNote":
  test "includes all required fields":
    let note = formatAgentRunNote("opus-4", makeResult())
    check note.contains("Model: opus-4")
    check note.contains("Backend: claude-code")
    check note.contains("Exit Code: 0")
    check note.contains("Attempt: 1")
    check note.contains("Attempt Count: 1")
    check note.contains("Timeout: none")
    check note.contains("Log File: /tmp/log.txt")
    check note.contains("Last Message File: /tmp/last_msg.txt")

  test "includes last message section when non-empty":
    let note = formatAgentRunNote("opus-4", makeResult(lastMessage = "hello world"))
    check note.contains("### Agent Last Message")
    check note.contains("hello world")

  test "includes stdout tail section when non-empty":
    let note = formatAgentRunNote("opus-4", makeResult(stdout = "build ok"))
    check note.contains("### Agent Stdout Tail")
    check note.contains("build ok")

  test "omits last message section when empty":
    let note = formatAgentRunNote("opus-4", makeResult(lastMessage = ""))
    check not note.contains("### Agent Last Message")

  test "omits stdout tail section when empty":
    let note = formatAgentRunNote("opus-4", makeResult(stdout = ""))
    check not note.contains("### Agent Stdout Tail")

  test "truncates long lastMessage to AgentMessagePreviewChars":
    let long = 'x'.repeat(AgentMessagePreviewChars + 500)
    let note = formatAgentRunNote("m", makeResult(lastMessage = long))
    # The preview inside the note should be at most AgentMessagePreviewChars.
    let expected = truncateTail(long.strip(), AgentMessagePreviewChars)
    check note.contains(expected)
    check not note.contains(long)

  test "truncates long stdout to AgentStdoutPreviewChars":
    let long = 'y'.repeat(AgentStdoutPreviewChars + 500)
    let note = formatAgentRunNote("m", makeResult(stdout = long))
    let expected = truncateTail(long.strip(), AgentStdoutPreviewChars)
    check note.contains(expected)
    check not note.contains(long)

suite "appendAgentRunNote":
  test "appends run note to existing ticket content":
    let ticket = "# My Ticket\n\nSome content."
    let res = appendAgentRunNote(ticket, "opus-4", makeResult())
    check res.startsWith("# My Ticket")
    check res.contains("## Agent Run")
    # Base and note separated by blank line.
    check res.contains("Some content.\n\n## Agent Run")

  test "strips trailing whitespace from base content":
    let ticket = "# Ticket   \n\n  "
    let res = appendAgentRunNote(ticket, "m", makeResult())
    # After strip, base is "# Ticket" — no trailing spaces before separator.
    check res.startsWith("# Ticket\n\n## Agent Run")
