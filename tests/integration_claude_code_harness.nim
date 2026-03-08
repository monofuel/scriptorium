## Integration tests for running the real Claude Code binary.

import
  std/[os, sequtils, strutils, tempfiles, unittest],
  scriptorium/harness_claude_code

const
  DefaultIntegrationModel = "claude-sonnet-4-6"

proc integrationModel(): string =
  ## Return the configured integration model, or the default model.
  result = getEnv("SCRIPTORIUM_TEST_MODEL", DefaultIntegrationModel)

proc hasClaudeAuth(): bool =
  ## Return true when an Anthropic API key is available.
  result = getEnv("ANTHROPIC_API_KEY", "").len > 0

suite "integration claude-code harness":
  test "real claude-code one-shot smoke test":
    let claudePath = findExe("claude")
    doAssert claudePath.len > 0, "claude binary is required for integration tests"
    doAssert hasClaudeAuth(),
      "ANTHROPIC_API_KEY is required for claude-code integration tests"

    let tmpDir = createTempDir("scriptorium_integration_claude_code_", "", getTempDir())
    defer:
      removeDir(tmpDir)

    let worktreePath = tmpDir / "worktree"
    createDir(worktreePath)
    let request = ClaudeCodeRunRequest(
      prompt: "Reply with exactly: ok",
      workingDir: worktreePath,
      model: integrationModel(),
      ticketId: "integration-smoke",
      logRoot: tmpDir / "logs",
      hardTimeoutMs: 60_000,
      noOutputTimeoutMs: 30_000,
    )

    var events: seq[string] = @[]
    var mutableRequest = request
    mutableRequest.onEvent = proc(event: ClaudeCodeStreamEvent) =
      ## Capture events for assertion.
      events.add($event.kind & ":" & event.text)

    let runResult = runClaudeCode(mutableRequest)
    doAssert runResult.exitCode == 0,
      "claude-code failed with non-zero exit code.\n" &
      "Model: " & integrationModel() & "\n" &
      "Command: " & runResult.command.join(" ") & "\n" &
      "Stdout:\n" & runResult.stdout
    doAssert runResult.lastMessage.strip().len > 0,
      "claude-code did not produce a last message.\n" &
      "Last message file: " & runResult.lastMessageFile & "\n" &
      "Stdout:\n" & runResult.stdout
    check fileExists(runResult.logFile)
    check fileExists(runResult.lastMessageFile)
    check events.len > 0
    check events.anyIt("status" in it and "init" in it)
    check events.anyIt("message" in it)
