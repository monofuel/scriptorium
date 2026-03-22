## Live integration test for the review agent flow.

import
  std/[json, os, osproc, strformat, strutils, tempfiles, times, unittest],
  mcport,
  scriptorium/[agent_runner, config, orchestrator, prompt_builders, shared_state]

const
  LiveMcpBasePort = 24000
  ServerStartupSleepMs = 250
  ReviewHardTimeoutMs = 300_000
  ReviewNoOutputTimeoutMs = 120_000

type
  ServerThreadArgs = tuple[
    httpServer: HttpMcpServer,
    address: string,
    port: int,
  ]

var
  liveServers: seq[HttpMcpServer] = @[]

proc runHttpServer(args: ServerThreadArgs) {.thread.} =
  ## Run one MCP HTTP server in a background thread.
  args.httpServer.serve(args.port, args.address)

proc integrationModel(): string =
  ## Return the configured integration model, or the default.
  result = getEnv("SCRIPTORIUM_TEST_MODEL", "")
  if result.len == 0:
    result = getEnv("CODEX_INTEGRATION_MODEL", "gpt-5.4")
  result = resolveModel(result)

proc integrationHarness(): Harness =
  ## Return the test harness from env, or infer from model.
  let envVal = getEnv("SCRIPTORIUM_TEST_HARNESS", "").strip().toLowerAscii()
  if envVal.len > 0:
    case envVal
    of "codex": result = harnessCodex
    of "claude-code": result = harnessClaudeCode
    of "typoi": result = harnessTypoi
    else:
      raise newException(ValueError, "unknown SCRIPTORIUM_TEST_HARNESS: " & envVal)
  else:
    result = inferHarness(integrationModel())

proc hasAgentAuth(): bool =
  ## Return true when API keys are available for the configured test harness.
  let h = integrationHarness()
  case h
  of harnessCodex:
    let hasApiKey = getEnv("OPENAI_API_KEY", "").len > 0 or getEnv("CODEX_API_KEY", "").len > 0
    let hasOauth = fileExists(expandTilde("~/.codex/auth.json"))
    result = hasApiKey or hasOauth
  of harnessClaudeCode:
    let hasApiKey = getEnv("ANTHROPIC_API_KEY", "").len > 0
    let hasOauth = fileExists(expandTilde("~/.claude/.credentials.json"))
    result = hasApiKey or hasOauth
  of harnessTypoi:
    result = true

proc requiredAgentBinary(): string =
  ## Return the binary name needed for the configured test harness.
  let h = integrationHarness()
  case h
  of harnessCodex: result = "codex"
  of harnessClaudeCode: result = "claude"
  of harnessTypoi: result = "typoi"

proc mcpPort(offset: int): int =
  ## Return a deterministic local MCP port for one test offset.
  result = LiveMcpBasePort + (getCurrentProcessId().int mod 1000) + offset

proc mcpBaseUrl(port: int): string =
  ## Return the base MCP HTTP URL for one local port.
  result = &"http://127.0.0.1:{port}"

proc makeTestRepo(path: string) =
  ## Create a minimal git repository with a real diff on a branch.
  createDir(path)
  let q = quoteShell(path)
  let run = proc(cmd: string) =
    let (output, rc) = execCmdEx(cmd)
    doAssert rc == 0, cmd & "\n" & output
  run("git -C " & q & " init")
  run("git -C " & q & " config user.email test@test.com")
  run("git -C " & q & " config user.name Test")
  writeFile(path / "hello.nim", "echo \"hello\"\n")
  run("git -C " & q & " add hello.nim")
  run("git -C " & q & " commit -m initial")
  run("git -C " & q & " checkout -b review-test-branch")
  writeFile(path / "hello.nim", "echo \"hello world\"\n")
  run("git -C " & q & " add hello.nim")
  run("git -C " & q & " commit -m \"update hello message\"")

suite "integration review agent live":
  test "IT-REVIEW-01 real review agent calls submit_review with a real model":
    let agentBinary = requiredAgentBinary()
    let binaryPath = findExe(agentBinary)
    doAssert binaryPath.len > 0,
      agentBinary & " binary is required for live review agent integration tests"
    doAssert hasAgentAuth(),
      "API credentials are required for live review agent integration tests"

    discard consumeReviewDecision()

    let port = mcpPort(1)
    let endpoint = mcpBaseUrl(port)

    let httpServer = createOrchestratorServer()
    var serverThread: Thread[ServerThreadArgs]
    createThread(serverThread, runHttpServer, (httpServer, "127.0.0.1", port))
    sleep(ServerStartupSleepMs)
    liveServers.add(httpServer)

    let tmpDir = createTempDir("scriptorium_integration_review_agent_", "", getTempDir())
    defer:
      removeDir(tmpDir)

    let repoPath = tmpDir / "repo"
    makeTestRepo(repoPath)

    let diffResult = execCmdEx("git -C " & quoteShell(repoPath) & " diff master...review-test-branch")
    doAssert diffResult[1] == 0, "failed to generate diff"
    let diffContent = diffResult[0]

    let ticketContent = "# Update hello message\n\nChange hello.nim to print \"hello world\" instead of \"hello\".\n"
    let areaContent = "(no area specified)"
    let submitSummary = "Updated hello.nim to print hello world."

    let prompt = buildReviewAgentPrompt(ticketContent, diffContent, areaContent, submitSummary, "(AGENTS.md not found)", "(spec not available)")

    let model = integrationModel()
    let harness = integrationHarness()

    let request = AgentRunRequest(
      prompt: prompt,
      workingDir: repoPath,
      harness: harness,
      model: model,
      mcpEndpoint: endpoint,
      ticketId: "integration-review-agent-live",
      attempt: 1,
      skipGitRepoCheck: true,
      logRoot: tmpDir / "logs",
      noOutputTimeoutMs: ReviewNoOutputTimeoutMs,
      hardTimeoutMs: ReviewHardTimeoutMs,
      maxAttempts: 1,
    )

    let agentResult = runAgent(request)
    doAssert agentResult.exitCode == 0,
      "review agent failed to complete.\n" &
      "Exit code: " & $agentResult.exitCode & "\n" &
      "Stdout:\n" & agentResult.stdout

    let decision = consumeReviewDecision()
    doAssert decision.action == "approve" or decision.action == "request_changes",
      "review agent did not call submit_review with a valid action.\n" &
      "Action: \"" & decision.action & "\"\n" &
      "Feedback: \"" & decision.feedback & "\"\n" &
      "Stdout:\n" & agentResult.stdout

    check decision.action in ["approve", "request_changes"]

    let secondDecision = consumeReviewDecision()
    check secondDecision.action == ""
