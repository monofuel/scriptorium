## Integration tests for running the real codex binary.

import
  std/[os, strutils, tempfiles, unittest],
  scriptorium/harness_codex

const
  DefaultIntegrationModel = "gpt-5.1-codex-mini"
  CodexAuthPathEnv = "CODEX_AUTH_FILE"

proc integrationModel(): string =
  ## Return the configured integration model, or the default model.
  result = getEnv("CODEX_INTEGRATION_MODEL", DefaultIntegrationModel)

proc codexAuthPath(): string =
  ## Return the configured Codex auth file path used for OAuth credentials.
  let overridePath = getEnv(CodexAuthPathEnv, "").strip()
  if overridePath.len > 0:
    result = overridePath
  else:
    result = expandTilde("~/.codex/auth.json")

proc hasCodexAuth(): bool =
  ## Return true when API keys or a Codex OAuth auth file are available.
  let hasApiKey = getEnv("OPENAI_API_KEY", "").len > 0 or getEnv("CODEX_API_KEY", "").len > 0
  result = hasApiKey or fileExists(codexAuthPath())

suite "integration codex harness":
  test "real codex exec one-shot smoke test":
    let codexPath = findExe("codex")
    doAssert codexPath.len > 0, "codex binary is required for integration tests"
    doAssert hasCodexAuth(),
      "OPENAI_API_KEY/CODEX_API_KEY or a Codex OAuth auth file is required for integration tests (" &
      codexAuthPath() & ")"

    let tmpDir = createTempDir("scriptorium_integration_codex_", "", getTempDir())
    defer:
      removeDir(tmpDir)

    let worktreePath = tmpDir / "worktree"
    createDir(worktreePath)
    let request = CodexRunRequest(
      prompt: "Reply with exactly: ok",
      workingDir: worktreePath,
      model: integrationModel(),
      ticketId: "integration-smoke",
      skipGitRepoCheck: true,
      logRoot: tmpDir / "logs",
      hardTimeoutMs: 45_000,
      noOutputTimeoutMs: 15_000,
    )

    let runResult = runCodex(request)
    doAssert runResult.exitCode == 0,
      "codex exec failed with non-zero exit code.\n" &
      "Model: " & integrationModel() & "\n" &
      "Command: " & runResult.command.join(" ") & "\n" &
      "Stdout:\n" & runResult.stdout
    doAssert runResult.lastMessage.strip().len > 0,
      "codex did not produce a last message.\n" &
      "Last message file: " & runResult.lastMessageFile & "\n" &
      "Stdout:\n" & runResult.stdout
    check fileExists(runResult.logFile)
    check fileExists(runResult.lastMessageFile)
