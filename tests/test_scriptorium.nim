## Tests for the scriptorium CLI and core utilities.

import
  std/[algorithm, json, locks, os, osproc, sequtils, sha1, strformat, strutils, tables, tempfiles, times, unittest],
  jsony,
  scriptorium/[agent_runner, config, init, logging, orchestrator, ticket_metadata]

const
  OrchestratorTestBasePort = 19000

type
  StreamMessageJson = object
    `type`*: string
    text*: string

proc makeTestRepo(path: string) =
  ## Create a minimal git repository at path suitable for testing.
  if dirExists(path):
    removeDir(path)
  createDir(path)
  discard execCmdEx("git -C " & path & " init")
  discard execCmdEx("git -C " & path & " config user.email test@test.com")
  discard execCmdEx("git -C " & path & " config user.name Test")
  discard execCmdEx("git -C " & path & " commit --allow-empty -m initial")

proc runCmdOrDie(cmd: string) =
  ## Run a shell command and fail the test immediately if it exits non-zero.
  let (_, rc) = execCmdEx(cmd)
  doAssert rc == 0, cmd

proc normalizedPathForTest(path: string): string =
  ## Return an absolute path with forward slash separators for assertions.
  result = absolutePath(path).replace('\\', '/')

proc writeScriptoriumConfig(repoPath: string, cfg: Config) =
  ## Write one typed scriptorium.json payload for test configuration.
  writeFile(repoPath / "scriptorium.json", cfg.toJson())

proc writeOrchestratorEndpointConfig(repoPath: string, portOffset: int, maxAttempts: int = 2) =
  ## Write a unique local orchestrator endpoint configuration for one test.
  let basePort = OrchestratorTestBasePort + (getCurrentProcessId().int mod 1000)
  let orchestratorPort = basePort + portOffset
  var cfg = defaultConfig()
  cfg.endpoints.local = &"http://127.0.0.1:{orchestratorPort}"
  cfg.timeouts.codingAgentMaxAttempts = maxAttempts
  writeScriptoriumConfig(repoPath, cfg)

proc withPlanWorktree(repoPath: string, suffix: string, action: proc(planPath: string)) =
  ## Open scriptorium/plan in a temporary worktree for direct test mutations.
  let tmpPlan = getTempDir() / ("scriptorium_test_plan_" & suffix)
  if dirExists(tmpPlan):
    removeDir(tmpPlan)

  runCmdOrDie("git -C " & quoteShell(repoPath) & " worktree add " & quoteShell(tmpPlan) & " scriptorium/plan")
  defer:
    discard execCmdEx("git -C " & quoteShell(repoPath) & " worktree remove --force " & quoteShell(tmpPlan))

  action(tmpPlan)

proc removeSpecFromPlan(repoPath: string) =
  ## Remove spec.md from scriptorium/plan and commit the change.
  withPlanWorktree(repoPath, "remove_spec", proc(planPath: string) =
    runCmdOrDie("git -C " & quoteShell(planPath) & " rm spec.md")
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-remove-spec")
  )

proc addAreaToPlan(repoPath: string, fileName: string, content: string) =
  ## Add one area markdown file to scriptorium/plan and commit the change.
  withPlanWorktree(repoPath, "add_area", proc(planPath: string) =
    let relPath = "areas/" & fileName
    writeFile(planPath / relPath, content)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add " & quoteShell(relPath))
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-add-area")
  )

proc writeSpecInPlan(repoPath: string, content: string) =
  ## Replace spec.md on scriptorium/plan and commit the change.
  withPlanWorktree(repoPath, "write_spec", proc(planPath: string) =
    writeFile(planPath / "spec.md", content)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add spec.md")
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-write-spec")
  )

proc addTicketToPlan(repoPath: string, state: string, fileName: string, content: string) =
  ## Add one ticket file to a plan ticket state directory and commit it.
  withPlanWorktree(repoPath, "add_ticket", proc(planPath: string) =
    let relPath = "tickets" / state / fileName
    writeFile(planPath / relPath, content)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add " & quoteShell(relPath))
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-add-ticket")
  )

proc moveTicketStateInPlan(repoPath: string, fromState: string, toState: string, fileName: string) =
  ## Move a ticket file from one state directory to another and commit.
  withPlanWorktree(repoPath, "move_ticket_state", proc(planPath: string) =
    let fromPath = "tickets" / fromState / fileName
    let toPath = "tickets" / toState / fileName
    moveFile(planPath / fromPath, planPath / toPath)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add -A " & quoteShell("tickets"))
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-move-ticket")
  )

proc writeSpecHashInPlan(repoPath: string, hash: string) =
  ## Write areas/.spec-hash on scriptorium/plan and commit.
  withPlanWorktree(repoPath, "write_spec_hash", proc(planPath: string) =
    createDir(planPath / "areas")
    writeFile(planPath / "areas/.spec-hash", hash & "\n")
    runCmdOrDie("git -C " & quoteShell(planPath) & " add areas/.spec-hash")
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-write-spec-hash")
  )

proc writeAreaHashesInPlan(repoPath: string, hashes: Table[string, string]) =
  ## Write tickets/.area-hashes on scriptorium/plan and commit.
  withPlanWorktree(repoPath, "write_area_hashes", proc(planPath: string) =
    createDir(planPath / "tickets")
    var lines: seq[string] = @[]
    for areaId, hash in hashes:
      lines.add(areaId & ":" & hash)
    lines.sort()
    writeFile(planPath / "tickets/.area-hashes", lines.join("\n") & "\n")
    runCmdOrDie("git -C " & quoteShell(planPath) & " add tickets/.area-hashes")
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-write-area-hashes")
  )

proc planCommitCount(repoPath: string): int =
  ## Return the commit count reachable from the plan branch.
  let (output, rc) = execCmdEx("git -C " & quoteShell(repoPath) & " rev-list --count scriptorium/plan")
  doAssert rc == 0
  result = parseInt(output.strip())

proc planTreeFiles(repoPath: string): seq[string] =
  ## Return file paths from the plan branch tree.
  let (output, rc) = execCmdEx("git -C " & quoteShell(repoPath) & " ls-tree -r --name-only scriptorium/plan")
  doAssert rc == 0
  result = output.splitLines().filterIt(it.len > 0)

proc gitWorktreePaths(repoPath: string): seq[string] =
  ## Return absolute paths from git worktree list.
  let (output, rc) = execCmdEx("git -C " & quoteShell(repoPath) & " worktree list --porcelain")
  doAssert rc == 0
  for line in output.splitLines():
    if line.startsWith("worktree "):
      result.add(line["worktree ".len..^1].strip())

proc addPassingMakefile(repoPath: string) =
  ## Add a Makefile with passing quality-gate targets and commit it on master.
  writeFile(
    repoPath / "Makefile",
    "test:\n\t@echo PASS test\n\nintegration-test:\n\t@echo PASS integration-test\n",
  )
  runCmdOrDie("git -C " & quoteShell(repoPath) & " add Makefile")
  runCmdOrDie("git -C " & quoteShell(repoPath) & " commit -m test-add-passing-makefile")

proc addFailingMakefile(repoPath: string) =
  ## Add a Makefile where `make test` fails and `make integration-test` is defined.
  writeFile(
    repoPath / "Makefile",
    "test:\n\t@echo FAIL test\n\t@false\n\nintegration-test:\n\t@echo PASS integration-test\n",
  )
  runCmdOrDie("git -C " & quoteShell(repoPath) & " add Makefile")
  runCmdOrDie("git -C " & quoteShell(repoPath) & " commit -m test-add-failing-makefile")

proc addIntegrationFailingMakefile(repoPath: string) =
  ## Add a Makefile where `make test` passes and `make integration-test` fails.
  writeFile(
    repoPath / "Makefile",
    "test:\n\t@echo PASS test\n\nintegration-test:\n\t@echo FAIL integration-test\n\t@false\n",
  )
  runCmdOrDie("git -C " & quoteShell(repoPath) & " add Makefile")
  runCmdOrDie("git -C " & quoteShell(repoPath) & " commit -m test-add-integration-failing-makefile")

proc withTempRepo(prefix: string, action: proc(repoPath: string)) =
  ## Create a temporary git repository, run action, and clean up afterwards.
  let repoPath = createTempDir(prefix, "", getTempDir())
  defer:
    removeDir(repoPath)
  makeTestRepo(repoPath)
  action(repoPath)

proc pendingQueueFiles(repoPath: string): seq[string] =
  ## Return pending merge-queue markdown entries sorted by file name.
  let files = planTreeFiles(repoPath)
  result = files.filterIt(it.startsWith("queue/merge/pending/") and it.endsWith(".md"))
  result.sort()

proc readPlanFile(repoPath: string, relPath: string): string =
  ## Read one file from the plan branch tree.
  let (output, rc) = execCmdEx(
    "git -C " & quoteShell(repoPath) & " show scriptorium/plan:" & relPath
  )
  doAssert rc == 0, relPath
  result = output

proc latestPlanCommits(repoPath: string, count: int): seq[string] =
  ## Return the latest commit subjects from the plan branch.
  let (output, rc) = execCmdEx(
    "git -C " & quoteShell(repoPath) & " log --format=%s -n " & $count & " scriptorium/plan"
  )
  doAssert rc == 0
  result = output.splitLines().filterIt(it.len > 0)

proc callSubmitPrTool(summary: string) =
  ## Simulate one coding-agent submit_pr MCP tool call.
  discard consumeSubmitPrSummary()
  let httpServer = createOrchestratorServer()
  doAssert httpServer.server.toolHandlers.hasKey("submit_pr")
  let submitPrHandler = httpServer.server.toolHandlers["submit_pr"]
  discard submitPrHandler(%*{"summary": summary})

proc noopRunner(request: AgentRunRequest): AgentRunResult =
  ## Fake agent runner that returns immediately with no review decision.
  ## When used with processMergeQueue the review agent stalls and defaults to approve.
  discard request
  AgentRunResult(exitCode: 0, backend: harnessCodex, timeoutKind: "none")

suite "scriptorium init":
  test "creates scriptorium/plan branch":
    let tmp = getTempDir() / "scriptorium_test_init_branch"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    runInit(tmp, quiet = true)

    let (_, rc) = execCmdEx("git -C " & tmp & " rev-parse --verify scriptorium/plan")
    check rc == 0

  test "plan branch contains correct folder structure":
    let tmp = getTempDir() / "scriptorium_test_init_structure"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    runInit(tmp, quiet = true)

    let (files, _) = execCmdEx("git -C " & tmp & " ls-tree -r --name-only scriptorium/plan")
    check "spec.md" in files
    check "areas/.gitkeep" in files
    check "tickets/open/.gitkeep" in files
    check "tickets/in-progress/.gitkeep" in files
    check "tickets/done/.gitkeep" in files
    check "decisions/.gitkeep" in files

  test "raises on already initialized workspace":
    let tmp = getTempDir() / "scriptorium_test_init_dupe"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    runInit(tmp, quiet = true)
    expect ValueError:
      runInit(tmp, quiet = true)

  test "raises on non-git directory":
    let tmp = getTempDir() / "scriptorium_test_not_a_repo"
    createDir(tmp)
    defer: removeDir(tmp)

    expect ValueError:
      runInit(tmp, quiet = true)

suite "config":
  test "defaults to claude models with claude-code harness for all roles":
    let cfg = defaultConfig()
    check cfg.agents.architect.model == "claude-opus-4-6"
    check cfg.agents.coding.model == "claude-sonnet-4-6"
    check cfg.agents.manager.model == "claude-sonnet-4-6"
    check cfg.agents.reviewer.model == "claude-sonnet-4-6"
    check cfg.agents.architect.harness == harnessClaudeCode
    check cfg.agents.coding.harness == harnessClaudeCode
    check cfg.agents.manager.harness == harnessClaudeCode
    check cfg.agents.reviewer.harness == harnessClaudeCode
    check cfg.agents.architect.reasoningEffort == ""
    check cfg.agents.coding.reasoningEffort == ""
    check cfg.agents.manager.reasoningEffort == ""
    check cfg.agents.reviewer.reasoningEffort == ""

  test "loads from scriptorium.json":
    let tmp = getTempDir() / "scriptorium_test_config"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.agents.architect = AgentConfig(harness: harnessClaudeCode, model: "claude-opus-4-6", reasoningEffort: "medium")
    writtenCfg.agents.coding = AgentConfig(harness: harnessTypoi, model: "grok-code-fast-1", reasoningEffort: "high")
    writtenCfg.agents.manager = AgentConfig(harness: harnessCodex, model: "gpt-5.1-codex-mini", reasoningEffort: "low")
    writtenCfg.endpoints.local = "http://localhost:1234/v1"
    writeScriptoriumConfig(tmp, writtenCfg)

    let cfg = loadConfig(tmp)
    check cfg.agents.architect.model == "claude-opus-4-6"
    check cfg.agents.architect.harness == harnessClaudeCode
    check cfg.agents.coding.model == "grok-code-fast-1"
    check cfg.agents.coding.harness == harnessTypoi
    check cfg.agents.manager.model == "gpt-5.1-codex-mini"
    check cfg.agents.manager.harness == harnessCodex
    check cfg.agents.architect.reasoningEffort == "medium"
    check cfg.agents.coding.reasoningEffort == "high"
    check cfg.agents.manager.reasoningEffort == "low"
    check cfg.endpoints.local == "http://localhost:1234/v1"

  test "loads reviewer config from scriptorium.json":
    let tmp = getTempDir() / "scriptorium_test_config_reviewer"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.agents.reviewer = AgentConfig(harness: harnessClaudeCode, model: "claude-sonnet-4-6", reasoningEffort: "low")
    writeScriptoriumConfig(tmp, writtenCfg)

    let cfg = loadConfig(tmp)
    check cfg.agents.reviewer.model == "claude-sonnet-4-6"
    check cfg.agents.reviewer.harness == harnessClaudeCode
    check cfg.agents.reviewer.reasoningEffort == "low"

  test "inferHarness works for reviewer models":
    check inferHarness("claude-sonnet-4-6") == harnessClaudeCode
    check inferHarness("codex-mini-review") == harnessCodex
    check inferHarness("grok-review-1") == harnessTypoi

  test "manager model remains independent when manager is unset":
    let tmp = getTempDir() / "scriptorium_test_config_manager_independent"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.agents.coding = AgentConfig(harness: harnessTypoi, model: "grok-code-fast-1", reasoningEffort: "high")
    writtenCfg.agents.manager = AgentConfig()
    writeScriptoriumConfig(tmp, writtenCfg)

    let cfg = loadConfig(tmp)
    check cfg.agents.coding.model == "grok-code-fast-1"
    check cfg.agents.manager.model == "claude-sonnet-4-6"
    check cfg.agents.coding.reasoningEffort == "high"
    check cfg.agents.manager.reasoningEffort == ""

  test "missing file returns defaults":
    let tmp = getTempDir() / "scriptorium_test_config_missing"
    createDir(tmp)
    defer: removeDir(tmp)

    let cfg = loadConfig(tmp)
    check cfg.agents.architect.model == "claude-opus-4-6"
    check cfg.agents.coding.model == "claude-sonnet-4-6"
    check cfg.agents.manager.model == "claude-sonnet-4-6"
    check cfg.agents.architect.reasoningEffort == ""
    check cfg.agents.coding.reasoningEffort == ""
    check cfg.agents.manager.reasoningEffort == ""

  test "inferHarness routing":
    check inferHarness("claude-opus-4-6") == harnessClaudeCode
    check inferHarness("claude-haiku-4-5") == harnessClaudeCode
    check inferHarness("codex-mini") == harnessCodex
    check inferHarness("gpt-4o") == harnessCodex
    check inferHarness("grok-code-fast-1") == harnessTypoi
    check inferHarness("local/qwen3.5-35b-a3b") == harnessTypoi

  test "concurrency defaults when key is absent":
    let tmp = getTempDir() / "scriptorium_test_config_concurrency_absent"
    createDir(tmp)
    defer: removeDir(tmp)

    let cfg = loadConfig(tmp)
    check cfg.concurrency.maxAgents == 4
    check cfg.concurrency.tokenBudgetMB == 0

  test "concurrency parses both keys":
    let tmp = getTempDir() / "scriptorium_test_config_concurrency_both"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.concurrency.maxAgents = 4
    writtenCfg.concurrency.tokenBudgetMB = 512
    writeScriptoriumConfig(tmp, writtenCfg)

    let cfg = loadConfig(tmp)
    check cfg.concurrency.maxAgents == 4
    check cfg.concurrency.tokenBudgetMB == 512

  test "concurrency parses only maxAgents":
    let tmp = getTempDir() / "scriptorium_test_config_concurrency_maxonly"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.concurrency.maxAgents = 8
    writeScriptoriumConfig(tmp, writtenCfg)

    let cfg = loadConfig(tmp)
    check cfg.concurrency.maxAgents == 8
    check cfg.concurrency.tokenBudgetMB == 0

  test "timeout defaults when key is absent":
    let tmp = getTempDir() / "scriptorium_test_config_timeout_absent"
    createDir(tmp)
    defer: removeDir(tmp)

    let cfg = loadConfig(tmp)
    check cfg.timeouts.codingAgentHardTimeoutMs == 14_400_000
    check cfg.timeouts.codingAgentNoOutputTimeoutMs == 300_000
    check cfg.timeouts.codingAgentProgressTimeoutMs == 600_000
    check cfg.timeouts.codingAgentMaxAttempts == 5

  test "timeout parses custom values":
    let tmp = getTempDir() / "scriptorium_test_config_timeout_custom"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.timeouts.codingAgentHardTimeoutMs = 7_200_000
    writtenCfg.timeouts.codingAgentNoOutputTimeoutMs = 600_000
    writtenCfg.timeouts.codingAgentProgressTimeoutMs = 900_000
    writtenCfg.timeouts.codingAgentMaxAttempts = 3
    writeScriptoriumConfig(tmp, writtenCfg)

    let cfg = loadConfig(tmp)
    check cfg.timeouts.codingAgentHardTimeoutMs == 7_200_000
    check cfg.timeouts.codingAgentNoOutputTimeoutMs == 600_000
    check cfg.timeouts.codingAgentProgressTimeoutMs == 900_000
    check cfg.timeouts.codingAgentMaxAttempts == 3

  test "default endpoint populated when not in scriptorium.json":
    let tmp = getTempDir() / "scriptorium_test_config_endpoint_default"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.endpoints.local = ""
    writeScriptoriumConfig(tmp, writtenCfg)

    let cfg = loadConfig(tmp)
    check cfg.endpoints.local == "http://127.0.0.1:8097"

  test "missing file returns default endpoint":
    let tmp = getTempDir() / "scriptorium_test_config_endpoint_missing"
    createDir(tmp)
    defer: removeDir(tmp)

    let cfg = loadConfig(tmp)
    check cfg.endpoints.local == "http://127.0.0.1:8097"

  test "defaultConfig has syncAgentsMd true":
    let cfg = defaultConfig()
    check cfg.syncAgentsMd == true

  test "loadConfig with syncAgentsMd false returns false":
    let tmp = getTempDir() / "scriptorium_test_config_sync_false"
    createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "scriptorium.json", """{"syncAgentsMd": false}""")

    let cfg = loadConfig(tmp)
    check cfg.syncAgentsMd == false

  test "loadConfig without syncAgentsMd key returns true":
    let tmp = getTempDir() / "scriptorium_test_config_sync_missing"
    createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "scriptorium.json", """{}""")

    let cfg = loadConfig(tmp)
    check cfg.syncAgentsMd == true

suite "orchestrator endpoint":
  test "empty endpoint falls back to default":
    let endpoint = parseEndpoint("")
    check endpoint.address == "127.0.0.1"
    check endpoint.port == 8097

  test "parses endpoint from config value":
    let tmp = getTempDir() / "scriptorium_test_orchestrator_endpoint"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.endpoints.local = "http://localhost:1234/v1"
    writeScriptoriumConfig(tmp, writtenCfg)

    let endpoint = loadOrchestratorEndpoint(tmp)
    check endpoint.address == "localhost"
    check endpoint.port == 1234

  test "rejects endpoint missing host":
    expect ValueError:
      discard parseEndpoint("http:///v1")

suite "orchestrator plan spec update":
  test "updateSpecFromArchitect runs in plan worktree, reads repo path, and commits":
    let tmp = getTempDir() / "scriptorium_test_plan_update_spec"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    writeFile(tmp / "source-marker.txt", "alpha\n")
    runCmdOrDie("git -C " & quoteShell(tmp) & " add source-marker.txt")
    runCmdOrDie("git -C " & quoteShell(tmp) & " commit -m test-add-source-marker")
    var writtenCfg = defaultConfig()
    writtenCfg.agents.architect.reasoningEffort = "high"
    writeScriptoriumConfig(tmp, writtenCfg)

    var callCount = 0
    var capturedFirstModel = ""
    var capturedFirstReasoningEffort = ""
    var capturedFirstWorkingDir = ""
    var capturedFirstRepoPath = ""
    var capturedFirstSpec = ""
    var capturedFirstUserRequest = ""
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Read source via repo path from prompt and update spec.md in plan worktree.
      inc callCount
      check req.heartbeatIntervalMs == 0
      check req.onEvent.isNil
      let repoPathMarker = "Project repository root path (read project source files and instructions from here):\n"
      let repoPathMarkerIndex = req.prompt.find(repoPathMarker)
      doAssert repoPathMarkerIndex >= 0
      let repoPathStart = repoPathMarkerIndex + repoPathMarker.len
      let repoPathEnd = req.prompt.find('\n', repoPathStart)
      doAssert repoPathEnd > repoPathStart
      let repoPathFromPrompt = req.prompt[repoPathStart..<repoPathEnd].strip()
      let priorSpec = readFile(req.workingDir / "spec.md")
      let sourceMarker = readFile(repoPathFromPrompt / "source-marker.txt").strip()
      writeFile(req.workingDir / "spec.md", "# Revised Spec\n\n- marker: " & sourceMarker & "\n")

      if callCount == 1:
        capturedFirstModel = req.model
        capturedFirstReasoningEffort = req.reasoningEffort
        capturedFirstWorkingDir = req.workingDir
        capturedFirstRepoPath = repoPathFromPrompt
        capturedFirstSpec = priorSpec
        capturedFirstUserRequest = req.prompt

      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "Updated spec.",
        timeoutKind: "none",
      )

    let before = planCommitCount(tmp)
    let changed = updateSpecFromArchitect(tmp, "expand scope", fakeRunner)
    let after = planCommitCount(tmp)
    let unchanged = updateSpecFromArchitect(tmp, "expand scope", fakeRunner)
    let afterUnchanged = planCommitCount(tmp)
    let (specBody, specRc) = execCmdEx("git -C " & quoteShell(tmp) & " show scriptorium/plan:spec.md")
    let (logOutput, logRc) = execCmdEx("git -C " & quoteShell(tmp) & " log --oneline -1 scriptorium/plan")

    check changed
    check not unchanged
    check callCount == 2
    check capturedFirstModel == "claude-opus-4-6"
    check capturedFirstReasoningEffort == "high"
    check capturedFirstWorkingDir != tmp
    check capturedFirstRepoPath == tmp
    check "scriptorium plan" in capturedFirstSpec
    check "expand scope" in capturedFirstUserRequest
    check "AGENTS.md" in capturedFirstUserRequest
    check "Active working directory path (this is the scriptorium plan worktree):" in capturedFirstUserRequest
    check "Only edit spec.md in this working directory." in capturedFirstUserRequest
    check "Treat `" in capturedFirstUserRequest
    check "as the authoritative planning file." in capturedFirstUserRequest
    check "If the request is discussion, analysis, or questions, reply directly and do not edit spec.md." in capturedFirstUserRequest
    check "Only edit spec.md when the engineer is asking to change plan content." in capturedFirstUserRequest
    check "Inline convenience copy of `spec.md` from the plan worktree:" in capturedFirstUserRequest
    check after == before + 1
    check afterUnchanged == after
    check specRc == 0
    check specBody == "# Revised Spec\n\n- marker: alpha\n"
    check logRc == 0
    check "scriptorium: update spec from architect" in logOutput

  test "updateSpecFromArchitect rejects writes outside spec.md":
    let tmp = getTempDir() / "scriptorium_test_plan_out_of_scope"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Write to spec.md and one out-of-scope path to trigger guard failure.
      writeFile(req.workingDir / "spec.md", "# Updated Spec\n")
      writeFile(req.workingDir / "areas/01-out-of-scope.md", "# Bad write\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "done",
        timeoutKind: "none",
      )

    let before = planCommitCount(tmp)
    expect ValueError:
      discard updateSpecFromArchitect(tmp, "expand scope", fakeRunner)
    let after = planCommitCount(tmp)
    let files = planTreeFiles(tmp)

    check after == before
    check "areas/01-out-of-scope.md" notin files

  test "updateSpecFromArchitect recovers stale managed deterministic worktree conflicts":
    let tmp = getTempDir() / "scriptorium_test_plan_stale_temp_conflict"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    var managedPlanPath = ""
    proc bootstrapRunner(req: AgentRunRequest): AgentRunResult =
      ## Capture the deterministic managed plan worktree path.
      managedPlanPath = req.workingDir
      writeFile(req.workingDir / "spec.md", "# Updated Spec\n\n- bootstrap\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "done",
        timeoutKind: "none",
      )
    discard updateSpecFromArchitect(tmp, "bootstrap managed path", bootstrapRunner)
    check managedPlanPath.len > 0
    check "/worktrees/plan" in normalizedPathForTest(managedPlanPath)

    runCmdOrDie("git -C " & quoteShell(tmp) & " worktree add " & quoteShell(managedPlanPath) & " scriptorium/plan")
    defer:
      discard execCmdEx("git -C " & quoteShell(tmp) & " worktree remove --force " & quoteShell(managedPlanPath))
      discard execCmdEx("git -C " & quoteShell(tmp) & " worktree prune")
      if dirExists(managedPlanPath):
        removeDir(managedPlanPath)
    removeDir(managedPlanPath)

    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Update spec.md in the recovered deterministic worktree.
      writeFile(req.workingDir / "spec.md", "# Updated Spec\n\n- recovered\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "done",
        timeoutKind: "none",
      )

    let changed = updateSpecFromArchitect(tmp, "recover stale temp", fakeRunner)
    let worktrees = gitWorktreePaths(tmp)

    check changed
    check managedPlanPath notin worktrees

  test "updateSpecFromArchitect keeps non-managed plan worktree conflicts intact":
    let tmp = getTempDir() / "scriptorium_test_plan_manual_conflict"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    let manualPath = getTempDir() / "scriptorium_manual_plan_conflict"
    if dirExists(manualPath):
      removeDir(manualPath)
    runCmdOrDie("git -C " & quoteShell(tmp) & " worktree add " & quoteShell(manualPath) & " scriptorium/plan")
    defer:
      discard execCmdEx("git -C " & quoteShell(tmp) & " worktree remove --force " & quoteShell(manualPath))
      discard execCmdEx("git -C " & quoteShell(tmp) & " worktree prune")
      if dirExists(manualPath):
        removeDir(manualPath)

    var runnerCalls = 0
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Track invocations; this runner should not be called on add conflict.
      inc runnerCalls
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    var errorMessage = ""
    try:
      discard updateSpecFromArchitect(tmp, "conflict", fakeRunner)
    except IOError as err:
      errorMessage = err.msg

    let worktrees = gitWorktreePaths(tmp)
    check runnerCalls == 0
    check "already used by worktree" in errorMessage
    check manualPath in worktrees

  test "stale worktree metadata is pruned before creating plan worktree":
    let tmp = getTempDir() / "scriptorium_test_stale_prune"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    # First call captures the managed plan path.
    var managedPlanPath = ""
    proc bootstrapRunner(req: AgentRunRequest): AgentRunResult =
      ## Capture the deterministic managed plan worktree path.
      managedPlanPath = req.workingDir
      writeFile(req.workingDir / "spec.md", "# Spec\n\n- bootstrap\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "done",
        timeoutKind: "none",
      )
    discard updateSpecFromArchitect(tmp, "bootstrap", bootstrapRunner)
    check managedPlanPath.len > 0

    # Simulate Docker scenario: worktree checkout dir is gone but .git/worktrees/plan metadata persists.
    runCmdOrDie("git -C " & quoteShell(tmp) & " worktree add " & quoteShell(managedPlanPath) & " scriptorium/plan")
    removeDir(managedPlanPath)
    # Metadata in .git/worktrees/plan now points to a nonexistent path.

    proc recoveryRunner(req: AgentRunRequest): AgentRunResult =
      ## Verify the worktree was created successfully after prune.
      writeFile(req.workingDir / "spec.md", "# Spec\n\n- recovered after prune\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "done",
        timeoutKind: "none",
      )

    let changed = updateSpecFromArchitect(tmp, "recover after prune", recoveryRunner)
    check changed
    # Worktree should be cleaned up after the operation.
    let worktrees = gitWorktreePaths(tmp)
    check managedPlanPath notin worktrees

  test "updateSpecFromArchitect fails fast when planner lock is held":
    let tmp = getTempDir() / "scriptorium_test_plan_lock_busy"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    var managedPlanPath = ""
    proc bootstrapRunner(req: AgentRunRequest): AgentRunResult =
      ## Capture deterministic plan path so tests can derive lock location.
      managedPlanPath = req.workingDir
      writeFile(req.workingDir / "spec.md", "# Updated Spec\n\n- bootstrap\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "done",
        timeoutKind: "none",
      )
    discard updateSpecFromArchitect(tmp, "bootstrap lock path", bootstrapRunner)
    check managedPlanPath.len > 0

    let managedRepoRoot = parentDir(parentDir(managedPlanPath))
    let lockPath = managedRepoRoot / "locks/repo.lock"
    createDir(parentDir(lockPath))
    createDir(lockPath)
    let pidPath = lockPath / "pid"
    let currentPid = getCurrentProcessId()
    writeFile(pidPath, $currentPid & "\n")
    defer:
      if fileExists(pidPath):
        removeFile(pidPath)
      if dirExists(lockPath):
        removeDir(lockPath)

    var runnerCalls = 0
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Track invocations; lock contention should fail before runner starts.
      inc runnerCalls
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    var errorMessage = ""
    try:
      discard updateSpecFromArchitect(tmp, "blocked by lock", fakeRunner)
    except IOError as err:
      errorMessage = err.msg

    check runnerCalls == 0
    check "another planner/manager is active" in errorMessage

suite "orchestrator invariants":
  test "ticket state invariant fails when same ticket exists in multiple state directories":
    let tmp = getTempDir() / "scriptorium_test_invariant_duplicate_ticket_states"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
    addTicketToPlan(tmp, "done", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    expect ValueError:
      validateTicketStateInvariant(tmp)

  test "transition commit invariant passes for orchestrator-managed state moves":
    let tmp = getTempDir() / "scriptorium_test_invariant_transition_pass"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    discard assignOldestOpenTicket(tmp)
    validateTransitionCommitInvariant(tmp)

  test "transition commit invariant fails for non-orchestrator ticket move commit":
    let tmp = getTempDir() / "scriptorium_test_invariant_transition_fail"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
    moveTicketStateInPlan(tmp, "open", "in-progress", "0001-first.md")

    expect ValueError:
      validateTransitionCommitInvariant(tmp)

  test "simulated crash during ticket move keeps prior valid state":
    let tmp = getTempDir() / "scriptorium_test_invariant_no_partial_move_on_crash"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
    let before = planCommitCount(tmp)

    expect IOError:
      withPlanWorktree(tmp, "simulated_crash_partial_move", proc(planPath: string) =
        moveFile(
          planPath / "tickets/open/0001-first.md",
          planPath / "tickets/in-progress/0001-first.md",
        )
        raise newException(IOError, "simulated crash before commit")
      )

    let files = planTreeFiles(tmp)
    let after = planCommitCount(tmp)
    check "tickets/open/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files
    check after == before
    validateTicketStateInvariant(tmp)

suite "orchestrator planning bootstrap":
  test "loads spec from plan branch":
    let tmp = getTempDir() / "scriptorium_test_plan_load_spec"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    let spec = loadSpecFromPlan(tmp)
    check "scriptorium plan" in spec

  test "missing spec raises error":
    let tmp = getTempDir() / "scriptorium_test_plan_missing_spec"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    removeSpecFromPlan(tmp)

    expect ValueError:
      discard loadSpecFromPlan(tmp)

  test "areas missing is true for blank plan and false when area exists":
    let tmp = getTempDir() / "scriptorium_test_areas_missing"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    check areasMissing(tmp)
    addAreaToPlan(tmp, "01-cli.md", "# Area 01\n")
    check not areasMissing(tmp)

  test "sync areas calls architect with configured model and spec":
    let tmp = getTempDir() / "scriptorium_test_sync_areas_call"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    var writtenCfg = defaultConfig()
    writtenCfg.agents.architect = AgentConfig(harness: harnessClaudeCode, model: "claude-opus-4-6")
    writeScriptoriumConfig(tmp, writtenCfg)

    var callCount = 0
    var capturedModel = ""
    var capturedSpec = ""
    proc generator(model: string, spec: string): seq[AreaDocument] =
      ## Capture architect invocation arguments and return one area.
      inc callCount
      capturedModel = model
      capturedSpec = spec
      result = @[
        AreaDocument(path: "01-cli.md", content: "# Area 01\n\n## Scope\n- CLI\n")
      ]

    let synced = syncAreasFromSpec(tmp, generator)
    check synced
    check callCount == 1
    check capturedModel == "claude-opus-4-6"
    check "scriptorium plan" in capturedSpec

    let (files, rc) = execCmdEx("git -C " & quoteShell(tmp) & " ls-tree -r --name-only scriptorium/plan")
    check rc == 0
    check "areas/01-cli.md" in files

  test "sync areas is idempotent on second run":
    let tmp = getTempDir() / "scriptorium_test_sync_areas_idempotent"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    var callCount = 0
    proc generator(model: string, spec: string): seq[AreaDocument] =
      ## Return stable area output for idempotence checks.
      inc callCount
      discard model
      discard spec
      result = @[
        AreaDocument(path: "01-cli.md", content: "# Area 01\n\n## Scope\n- CLI\n")
      ]

    let before = planCommitCount(tmp)
    let firstSync = syncAreasFromSpec(tmp, generator)
    let afterFirst = planCommitCount(tmp)
    let secondSync = syncAreasFromSpec(tmp, generator)
    let afterSecond = planCommitCount(tmp)

    check firstSync
    check not secondSync
    check callCount == 1
    check afterFirst == before + 2  # areas commit + spec hash marker commit
    check afterSecond == afterFirst

suite "orchestrator manager ticket bootstrap":
  test "areas needing tickets excludes areas with open or in-progress work":
    let tmp = getTempDir() / "scriptorium_test_areas_needing_tickets"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addAreaToPlan(tmp, "01-cli.md", "# Area 01\n")
    addAreaToPlan(tmp, "02-core.md", "# Area 02\n")
    addTicketToPlan(tmp, "open", "0001-cli-ticket.md", "# Ticket\n\n**Area:** 01-cli\n")

    let needed = areasNeedingTickets(tmp)
    check "areas/02-core.md" in needed
    check "areas/01-cli.md" notin needed

suite "orchestrator ticket assignment":
  test "oldest open ticket picks the lowest numeric ID":
    let tmp = getTempDir() / "scriptorium_test_oldest_open_ticket"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** b\n")
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let oldest = oldestOpenTicket(tmp)
    check oldest == "tickets/open/0001-first.md"

  test "assign moves ticket to in-progress in one commit":
    let tmp = getTempDir() / "scriptorium_test_assign_transition"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    moveTicketStateInPlan(tmp, "in-progress", "done", "0001-first.md")

    let removed = cleanupStaleTicketWorktrees(tmp)
    check assignment.worktree in removed
    check assignment.worktree notin gitWorktreePaths(tmp)

suite "parallel ticket assignment":
  test "two tickets with different areas are both assigned when maxAgents >= 2":
    let tmp = getTempDir() / "scriptorium_test_parallel_diff_areas"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** shared\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** shared\n")

    let assignments = assignOpenTickets(tmp, 2)
    check assignments.len == 1
    check assignments[0].openTicket == "tickets/open/0001-first.md"
    check assignments[0].inProgressTicket == "tickets/in-progress/0001-first.md"

  test "assignment respects maxAgents cap":
    let tmp = getTempDir() / "scriptorium_test_parallel_cap"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** area-b\n")
    addTicketToPlan(tmp, "open", "0003-third.md", "# Ticket 3\n\n**Area:** area-c\n")

    let assignments = assignOpenTickets(tmp, 2)
    check assignments.len == 2
    check assignments[0].openTicket == "tickets/open/0001-first.md"
    check assignments[1].openTicket == "tickets/open/0002-second.md"

  test "maxAgents = 1 assigns only one ticket":
    let tmp = getTempDir() / "scriptorium_test_parallel_single"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** area-b\n")

    let assignments = assignOpenTickets(tmp, 1)
    check assignments.len == 1
    check assignments[0].openTicket == "tickets/open/0001-first.md"
    check assignments[0].inProgressTicket == "tickets/in-progress/0001-first.md"
    check assignments[0].branch == "scriptorium/ticket-0001"

  test "assignOpenTickets skips area already in-progress":
    let tmp = getTempDir() / "scriptorium_test_parallel_skip_inprogress"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "in-progress", "0001-first.md", "# Ticket 1\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0003-third.md", "# Ticket 3\n\n**Area:** area-b\n")

    let assignments = assignOpenTickets(tmp, 3)
    check assignments.len == 1
    check assignments[0].openTicket == "tickets/open/0003-third.md"

  test "assignOpenTickets returns empty when no open tickets":
    let tmp = getTempDir() / "scriptorium_test_parallel_empty"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

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
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n**Depends:** 9999\n")

    let assignment = assignOldestOpenTicket(tmp)
    check assignment.inProgressTicket.len == 0

  test "assignOldestOpenTicket assigns ticket with satisfied dependency":
    let tmp = getTempDir() / "scriptorium_test_dep_satisfied"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "done", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** b\n**Depends:** 0001\n")

    let assignment = assignOldestOpenTicket(tmp)
    check assignment.inProgressTicket == "tickets/in-progress/0002-second.md"

  test "assignOldestOpenTicket skips blocked ticket and assigns next":
    let tmp = getTempDir() / "scriptorium_test_dep_skip_blocked"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n**Depends:** 9999\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** b\n")

    let assignment = assignOldestOpenTicket(tmp)
    check assignment.inProgressTicket == "tickets/in-progress/0002-second.md"

  test "assignOpenTickets skips ticket with unsatisfied dependency":
    let tmp = getTempDir() / "scriptorium_test_dep_parallel_skip"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** area-b\n**Depends:** 9999\n")

    let assignments = assignOpenTickets(tmp, 2)
    check assignments.len == 1
    check assignments[0].openTicket == "tickets/open/0001-first.md"

  test "assignOpenTickets assigns ticket after dependency is done":
    let tmp = getTempDir() / "scriptorium_test_dep_parallel_done"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "done", "0001-first.md", "# Ticket 1\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** area-b\n**Depends:** 0001\n")

    let assignments = assignOpenTickets(tmp, 2)
    check assignments.len == 1
    check assignments[0].openTicket == "tickets/open/0002-second.md"

suite "status dependency visibility":
  test "readOrchestratorStatus reports all cycle participants as blocked":
    let tmp = getTempDir() / "scriptorium_test_status_cycle_blocked"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0010-alpha.md", "# Alpha\n\n**Area:** a\n**Depends:** 0011\n")
    addTicketToPlan(tmp, "open", "0011-beta.md", "# Beta\n\n**Area:** b\n**Depends:** 0010\n")

    let status = readOrchestratorStatus(tmp)
    check status.blockedTickets.len == 2
    var blockedIds: seq[string]
    for bt in status.blockedTickets:
      blockedIds.add(bt.ticketId)
    check "0010" in blockedIds
    check "0011" in blockedIds

  test "readOrchestratorStatus reports tickets with unsatisfied deps as waiting":
    let tmp = getTempDir() / "scriptorium_test_status_waiting"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0020-first.md", "# First\n\n**Area:** a\n**Depends:** 9999\n")

    let status = readOrchestratorStatus(tmp)
    check status.waitingTickets.len == 1
    check status.waitingTickets[0].ticketId == "0020"
    check status.waitingTickets[0].dependsOn == @["9999"]

  test "readOrchestratorStatus does not report tickets with satisfied deps":
    let tmp = getTempDir() / "scriptorium_test_status_satisfied"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "done", "0030-prereq.md", "# Prereq\n\n**Area:** a\n")
    addTicketToPlan(tmp, "open", "0031-next.md", "# Next\n\n**Area:** b\n**Depends:** 0030\n")

    let status = readOrchestratorStatus(tmp)
    check status.blockedTickets.len == 0
    check status.waitingTickets.len == 0

  test "readOrchestratorStatus does not report tickets without dependencies":
    let tmp = getTempDir() / "scriptorium_test_status_no_deps"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0040-plain.md", "# Plain\n\n**Area:** a\n")

    let status = readOrchestratorStatus(tmp)
    check status.blockedTickets.len == 0
    check status.waitingTickets.len == 0

  test "readOrchestratorStatus reports all members of a three-node cycle":
    let tmp = getTempDir() / "scriptorium_test_status_cycle_three"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0050-a.md", "# A\n\n**Area:** a\n**Depends:** 0051\n")
    addTicketToPlan(tmp, "open", "0051-b.md", "# B\n\n**Area:** b\n**Depends:** 0052\n")
    addTicketToPlan(tmp, "open", "0052-c.md", "# C\n\n**Area:** c\n**Depends:** 0050\n")

    let status = readOrchestratorStatus(tmp)
    check status.blockedTickets.len == 3
    var blockedIds: seq[string]
    for bt in status.blockedTickets:
      blockedIds.add(bt.ticketId)
    check "0050" in blockedIds
    check "0051" in blockedIds
    check "0052" in blockedIds
    check status.waitingTickets.len == 0

suite "orchestrator mcp tools":
  test "createOrchestratorServer registers submit_pr and consumeSubmitPrSummary clears state":
    discard consumeSubmitPrSummary()
    let httpServer = createOrchestratorServer()

    check httpServer.server.tools.hasKey("submit_pr")
    check httpServer.server.toolHandlers.hasKey("submit_pr")
    let submitPrHandler = httpServer.server.toolHandlers["submit_pr"]
    let toolResponse = submitPrHandler(%*{"summary": "ship tool"})
    check toolResponse.getStr() == "Merge request enqueued."
    check consumeSubmitPrSummary() == "ship tool"
    check consumeSubmitPrSummary() == ""

  test "submit_review tool is registered and handler stores decision":
    discard consumeReviewDecision()
    let httpServer = createOrchestratorServer()

    check httpServer.server.tools.hasKey("submit_review")
    check httpServer.server.toolHandlers.hasKey("submit_review")
    let reviewHandler = httpServer.server.toolHandlers["submit_review"]
    let approveResponse = reviewHandler(%*{"action": "approve"})
    check approveResponse.getStr() == "Review decision recorded."
    let decision = consumeReviewDecision()
    check decision.action == "approve"
    check decision.feedback == ""
    check consumeReviewDecision().action == ""

    let changesResponse = reviewHandler(%*{"action": "request_changes", "feedback": "fix the tests"})
    check changesResponse.getStr() == "Review decision recorded."
    let decision2 = consumeReviewDecision()
    check decision2.action == "request_changes"
    check decision2.feedback == "fix the tests"

  test "submit_review rejects request_changes without feedback":
    let httpServer = createOrchestratorServer()
    let reviewHandler = httpServer.server.toolHandlers["submit_review"]
    let response = reviewHandler(%*{"action": "request_changes"})
    check "Feedback is required" in response.getStr()
    check consumeReviewDecision().action == ""

  test "submit_review rejects invalid action":
    let httpServer = createOrchestratorServer()
    let reviewHandler = httpServer.server.toolHandlers["submit_review"]
    let response = reviewHandler(%*{"action": "reject"})
    check "Invalid action" in response.getStr()
    check consumeReviewDecision().action == ""

  test "submit_pr enqueues immediately with active worktree":
    discard consumeSubmitPrSummary()
    let tmp = getTempDir() / "scriptorium_test_submit_pr_pass"
    createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "Makefile", "test:\n\t@echo PASS test\nintegration-test:\n\t@echo PASS integration-test\n")
    setActiveTicketWorktree(tmp, "0099")
    defer: clearActiveTicketWorktree()

    let httpServer = createOrchestratorServer()
    let submitPrHandler = httpServer.server.toolHandlers["submit_pr"]
    let toolResponse = submitPrHandler(%*{"summary": "tests pass"})
    check toolResponse.getStr() == "Merge request enqueued."
    check consumeSubmitPrSummary() == "tests pass"

  test "submit_pr enqueues even when tests would fail (merge queue is the gate)":
    discard consumeSubmitPrSummary()
    let tmp = getTempDir() / "scriptorium_test_submit_pr_fail"
    createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "Makefile", "test:\n\t@echo FAIL test\n\t@false\n")
    setActiveTicketWorktree(tmp, "0099")
    defer: clearActiveTicketWorktree()

    let httpServer = createOrchestratorServer()
    let submitPrHandler = httpServer.server.toolHandlers["submit_pr"]
    let toolResponse = submitPrHandler(%*{"summary": "tests fail"})
    check toolResponse.getStr() == "Merge request enqueued."
    check consumeSubmitPrSummary() == "tests fail"

suite "orchestrator coding agent execution":
  test "executeAssignedTicket runs agent and appends run summary":
    let tmp = getTempDir() / "scriptorium_test_execute_assigned_ticket"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
    var writtenCfg = defaultConfig()
    writtenCfg.agents.coding.reasoningEffort = "high"
    writtenCfg.endpoints.local = "http://127.0.0.1:19042"
    writtenCfg.timeouts.codingAgentMaxAttempts = 2
    writeScriptoriumConfig(tmp, writtenCfg)

    let assignment = assignOldestOpenTicket(tmp)
    let before = planCommitCount(tmp)

    var callCount = 0
    var capturedRequest = AgentRunRequest()
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Capture one request and return a deterministic successful run result.
      inc callCount
      capturedRequest = request
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: toJson(StreamMessageJson(`type`: "message", text: "done")),
        logFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.jsonl",
        lastMessageFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.last_message.txt",
        lastMessage: "Implemented the ticket.",
        timeoutKind: "none",
      )

    let runResult = executeAssignedTicket(tmp, assignment, fakeRunner)
    let after = planCommitCount(tmp)

    check callCount == 2
    check capturedRequest.model == "claude-sonnet-4-6"
    check capturedRequest.reasoningEffort == "high"
    check capturedRequest.mcpEndpoint == "http://127.0.0.1:19042"
    check capturedRequest.workingDir == assignment.worktree
    check capturedRequest.ticketId == "0001"
    check "Ticket 1" in capturedRequest.prompt
    check tmp in capturedRequest.prompt
    check "AGENTS.md" in capturedRequest.prompt
    check "Active working directory path (this is the ticket worktree and active repository checkout for this task):" in capturedRequest.prompt
    check "Treat this working directory as the repository checkout for code edits, builds, tests, and commits." in capturedRequest.prompt
    check runResult.exitCode == 0
    check after == before + 5

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/open/0001-first.md"
    )
    check ticketRc == 0
    check "## Agent Run" in ticketContent
    check "- Model: claude-sonnet-4-6" in ticketContent
    check "- Exit Code: 0" in ticketContent

    let commits = latestPlanCommits(tmp, 4)
    check commits[1].startsWith("scriptorium: reopen failed ticket")
    check "scriptorium: record agent run 0001-first" in commits[3]

  test "executeAssignedTicket enqueues merge request from submit_pr MCP tool":
    let tmp = getTempDir() / "scriptorium_test_execute_assigned_enqueue"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    let before = planCommitCount(tmp)
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Return a deterministic run result and signal completion with submit_pr.
      discard request
      callSubmitPrTool("ship it")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        logFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.jsonl",
        lastMessageFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.last_message.txt",
        lastMessage: "Work complete.",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunner)
    let after = planCommitCount(tmp)
    let files = planTreeFiles(tmp)

    check after == before + 4
    check "queue/merge/pending/0001-0001.md" in files
    let (queueEntry, queueRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:queue/merge/pending/0001-0001.md"
    )
    check queueRc == 0
    check "**Summary:** ship it" in queueEntry
    check "**Branch:** scriptorium/ticket-0001" in queueEntry

  test "executeAssignedTicket wires onEvent callback that accepts all event kinds":
    let tmp = getTempDir() / "scriptorium_test_execute_on_event"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    var capturedRequest = AgentRunRequest()
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Capture the request to inspect the onEvent callback.
      capturedRequest = request
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        logFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.jsonl",
        lastMessageFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.last_message.txt",
        lastMessage: "done",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunner)

    check capturedRequest.onEvent != nil

    let allKinds = [
      agentEventTool,
      agentEventStatus,
      agentEventHeartbeat,
      agentEventReasoning,
      agentEventMessage,
    ]
    for kind in allKinds:
      capturedRequest.onEvent(AgentStreamEvent(kind: kind, text: "test", rawLine: ""))

suite "orchestrator merge queue":
  test "ensureMergeQueueInitialized is idempotent":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_init"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    let before = planCommitCount(tmp)
    let first = ensureMergeQueueInitialized(tmp)
    let afterFirst = planCommitCount(tmp)
    let second = ensureMergeQueueInitialized(tmp)
    let afterSecond = planCommitCount(tmp)
    let files = planTreeFiles(tmp)

    check first
    check not second
    check afterFirst == before + 1
    check afterSecond == afterFirst
    check "queue/merge/pending/.gitkeep" in files
    check "queue/merge/active.md" in files

  test "processMergeQueue handles one item per call":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_single_flight"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** b\n")

    let firstAssignment = assignOldestOpenTicket(tmp)
    let secondAssignment = assignOldestOpenTicket(tmp)
    discard enqueueMergeRequest(tmp, firstAssignment, "first summary")
    discard enqueueMergeRequest(tmp, secondAssignment, "second summary")

    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)
    let queueFiles = files.filterIt(it.startsWith("queue/merge/pending/") and it.endsWith(".md"))

    check processed
    check "tickets/done/0001-first.md" in files
    check "tickets/in-progress/0002-second.md" in files
    check queueFiles.len == 1
    check queueFiles[0] == "queue/merge/pending/0002-0002.md"

  test "processMergeQueue success path merges to master and moves ticket to done":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_success"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "ticket-output.txt", "done\n")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m ticket-output")
    discard enqueueMergeRequest(tmp, assignment, "merge me")

    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)
    check processed
    check "tickets/done/0001-first.md" in files
    check "queue/merge/pending/0001-0001.md" notin files

    let (masterFile, masterRc) = execCmdEx("git -C " & quoteShell(tmp) & " show master:ticket-output.txt")
    check masterRc == 0
    check masterFile.strip() == "done"

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/done/0001-first.md"
    )
    check ticketRc == 0
    check "## Merge Queue Success" in ticketContent

  test "processMergeQueue failure path reopens ticket with failure note":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_failure"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addFailingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    discard enqueueMergeRequest(tmp, assignment, "expected failure")
    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)

    check processed
    check "tickets/open/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files
    check "queue/merge/pending/0001-0001.md" notin files

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/open/0001-first.md"
    )
    check ticketRc == 0
    check "## Merge Queue Failure" in ticketContent

  test "processMergeQueue failure path reopens ticket when integration-test fails":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_integration_failure"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addIntegrationFailingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    discard enqueueMergeRequest(tmp, assignment, "integration failure")
    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)

    check processed
    check "tickets/open/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files
    check "queue/merge/pending/0001-0001.md" notin files

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/open/0001-first.md"
    )
    check ticketRc == 0
    check "## Merge Queue Failure" in ticketContent
    check "make integration-test" in ticketContent
    check "FAIL integration-test" in ticketContent

  test "processMergeQueue review approve proceeds to merge":
    let tmp = getTempDir() / "scriptorium_test_review_approve"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "ticket-output.txt", "done\n")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m ticket-output")
    discard enqueueMergeRequest(tmp, assignment, "approve me")

    proc approveRunner(request: AgentRunRequest): AgentRunResult =
      ## Fake runner that records an approve decision.
      discard request
      recordReviewDecision("approve", "")
      AgentRunResult(exitCode: 0, backend: harnessCodex, timeoutKind: "none")

    discard consumeReviewDecision()
    let processed = processMergeQueue(tmp, approveRunner)
    check processed

    let files = planTreeFiles(tmp)
    check "tickets/done/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/done/0001-first.md"
    )
    check ticketRc == 0
    check "**Review:** approved" in ticketContent

  test "processMergeQueue review request_changes reopens ticket":
    let tmp = getTempDir() / "scriptorium_test_review_changes"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "ticket-output.txt", "done\n")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m ticket-output")
    discard enqueueMergeRequest(tmp, assignment, "needs changes")

    proc changesRunner(request: AgentRunRequest): AgentRunResult =
      ## Fake runner that records a request_changes decision.
      discard request
      recordReviewDecision("request_changes", "fix the formatting")
      AgentRunResult(exitCode: 0, backend: harnessCodex, timeoutKind: "none")

    discard consumeReviewDecision()
    let processed = processMergeQueue(tmp, changesRunner)
    check processed

    let files = planTreeFiles(tmp)
    check "tickets/open/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files
    check "tickets/done/0001-first.md" notin files

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/open/0001-first.md"
    )
    check ticketRc == 0
    check "**Review:** changes requested" in ticketContent
    check "**Review Feedback:** fix the formatting" in ticketContent

  test "processMergeQueue review stall defaults to approve":
    let tmp = getTempDir() / "scriptorium_test_review_stall"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "ticket-output.txt", "done\n")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m ticket-output")
    discard enqueueMergeRequest(tmp, assignment, "stall test")

    discard consumeReviewDecision()
    let processed = processMergeQueue(tmp, noopRunner)
    check processed

    let files = planTreeFiles(tmp)
    check "tickets/done/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/done/0001-first.md"
    )
    check ticketRc == 0
    check "**Review:** approved" in ticketContent

  test "executeAssignedTicket auto-commits dirty worktree before enqueue":
    let tmp = getTempDir() / "scriptorium_test_autocommit_dirty_worktree"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Write a file but do not commit, then signal submit_pr.
      discard request
      writeFile(assignment.worktree / "uncommitted.txt", "dirty\n")
      callSubmitPrTool("auto-commit test")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        logFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.jsonl",
        lastMessageFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.last_message.txt",
        lastMessage: "done",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunner)

    let (statusOutput, statusRc) = execCmdEx("git -C " & quoteShell(assignment.worktree) & " status --porcelain")
    check statusRc == 0
    check statusOutput.strip().len == 0

    let queueFiles = pendingQueueFiles(tmp)
    check queueFiles.len == 1

  test "processMergeQueue auto-commits dirty worktree before merge":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_autocommit"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "uncommitted.txt", "dirty\n")
    discard enqueueMergeRequest(tmp, assignment, "dirty merge")

    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)
    check processed
    check "tickets/done/0001-first.md" in files

    let (masterFile, masterRc) = execCmdEx("git -C " & quoteShell(tmp) & " show master:uncommitted.txt")
    check masterRc == 0
    check masterFile.strip() == "dirty"

  test "processMergeQueue parks ticket after MaxMergeFailures":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_stuck"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addFailingMakefile(tmp)

    let priorFailures = "## Merge Queue Failure\n\nfail 1\n\n## Merge Queue Failure\n\nfail 2\n"
    let ticketContent = "# Ticket 1\n\n**Area:** a\n\n" & priorFailures
    addTicketToPlan(tmp, "open", "0001-first.md", ticketContent)

    let assignment = assignOldestOpenTicket(tmp)
    discard enqueueMergeRequest(tmp, assignment, "expected stuck")
    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)

    check processed
    check "tickets/stuck/0001-first.md" in files
    check "tickets/open/0001-first.md" notin files
    check "tickets/in-progress/0001-first.md" notin files

    let (ticketOut, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/stuck/0001-first.md"
    )
    check ticketRc == 0
    check ticketOut.count("## Merge Queue Failure") == 3

    let commits = latestPlanCommits(tmp, 2)
    check commits.len > 1
    check "scriptorium: park stuck ticket 0001" in commits[1]

  test "stuck tickets excluded from areasNeedingTickets":
    let tmp = getTempDir() / "scriptorium_test_stuck_areas_excluded"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addAreaToPlan(tmp, "01-cli.md", "# Area 01\n")
    addAreaToPlan(tmp, "02-core.md", "# Area 02\n")
    addTicketToPlan(tmp, "stuck", "0001-cli-ticket.md", "# Ticket\n\n**Area:** 01-cli\n")

    let needed = areasNeedingTickets(tmp)
    check "areas/02-core.md" in needed
    check "areas/01-cli.md" notin needed

  test "processMergeQueue recovers missing worktree from branch":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_recover_worktree"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "ticket-output.txt", "recovered\n")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add ticket-output.txt")
    runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m ticket-output")
    discard enqueueMergeRequest(tmp, assignment, "recover me")

    # Simulate container restart: remove the worktree directory but keep the branch
    removeDir(assignment.worktree)
    runCmdOrDie("git -C " & quoteShell(tmp) & " worktree prune")

    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)
    check processed
    check "tickets/done/0001-first.md" in files
    check "queue/merge/pending/0001-0001.md" notin files

    let (masterFile, masterRc) = execCmdEx("git -C " & quoteShell(tmp) & " show master:ticket-output.txt")
    check masterRc == 0
    check masterFile.strip() == "recovered"

  test "processMergeQueue reopens ticket when worktree and branch are both missing":
    let tmp = getTempDir() / "scriptorium_test_merge_queue_no_branch"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    let assignment = assignOldestOpenTicket(tmp)
    discard enqueueMergeRequest(tmp, assignment, "lost branch")

    # Simulate container restart: remove both worktree and branch
    removeDir(assignment.worktree)
    runCmdOrDie("git -C " & quoteShell(tmp) & " worktree prune")
    runCmdOrDie("git -C " & quoteShell(tmp) & " branch -D " & quoteShell(assignment.branch))

    let processed = processMergeQueue(tmp, noopRunner)
    let files = planTreeFiles(tmp)
    check processed
    check "tickets/open/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files
    check "queue/merge/pending/0001-0001.md" notin files

    let (ticketContent, ticketRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " show scriptorium/plan:tickets/open/0001-first.md"
    )
    check ticketRc == 0
    check "## Merge Queue Failure" in ticketContent
    check "worktree and branch missing" in ticketContent

suite "orchestrator final v1 flow":
  test "blank spec tick skips orchestration and does not invoke agents":
    let tmp = getTempDir() / "scriptorium_test_v1_36_blank_spec_guard"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    writeOrchestratorEndpointConfig(tmp, 21)

    var callCount = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Count calls to verify no architect/manager/coding runner executes.
      inc callCount
      discard request
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    runOrchestratorForTicks(tmp, 1, fakeRunner)

    check callCount == 0

  test "integration-test failure on master blocks assignment of open tickets":
    let tmp = getTempDir() / "scriptorium_test_master_red_integration"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addIntegrationFailingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nNeed assignment.\n")
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

    runOrchestratorForTicks(tmp, 1)

    let files = planTreeFiles(tmp)
    check "tickets/open/0001-first.md" in files
    check "tickets/in-progress/0001-first.md" notin files

  test "runArchitectAreas commits files written by mocked architect runner":
    let tmp = getTempDir() / "scriptorium_test_v1_37_run_architect_areas"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    writeSpecInPlan(tmp, "# Spec\n\nBuild area files.\n")
    var writtenCfg = defaultConfig()
    writtenCfg.agents.architect.reasoningEffort = "high"
    writeScriptoriumConfig(tmp, writtenCfg)

    var callCount = 0
    var capturedRequest = AgentRunRequest()
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Write one area file directly into areas/ from the plan worktree.
      inc callCount
      capturedRequest = request
      writeFile(request.workingDir / "areas/01-arch.md", "# Area 01\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "areas written",
        timeoutKind: "none",
      )

    let before = planCommitCount(tmp)
    let changed = runArchitectAreas(tmp, fakeRunner)
    let after = planCommitCount(tmp)
    let files = planTreeFiles(tmp)

    check changed
    check callCount == 1
    check capturedRequest.ticketId == "architect-areas"
    check capturedRequest.model == "claude-opus-4-6"
    check capturedRequest.reasoningEffort == "high"
    check capturedRequest.logRoot == tmp / ".scriptorium" / "logs" / "architect-areas"
    check tmp in capturedRequest.prompt
    check "AGENTS.md" in capturedRequest.prompt
    check "Active working directory path (this is the scriptorium plan worktree):" in capturedRequest.prompt
    check "Read `spec.md` in this working directory and write/update area markdown files directly under `areas/` in this working directory." in capturedRequest.prompt
    check "areas/01-arch.md" in files
    check after == before + 2  # areas commit + spec hash marker commit

  test "done tickets suppress areas from areasNeedingTickets":
    let tmp = getTempDir() / "scriptorium_test_done_ticket_suppression"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addAreaToPlan(tmp, "01-done-area.md", "# Area 01\n")
    addAreaToPlan(tmp, "02-pending-area.md", "# Area 02\n")
    addTicketToPlan(tmp, "done", "0001-done-area-summary.md", "# Done\n\n**Area:** 01-done-area\n")

    let needed = areasNeedingTickets(tmp)
    check "areas/02-pending-area.md" in needed
    check "areas/01-done-area.md" notin needed

  test "done ticket with unchanged area hash suppresses area":
    let tmp = getTempDir() / "scriptorium_test_done_unchanged_hash"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addAreaToPlan(tmp, "01-done-area.md", "# Area 01\n")
    addAreaToPlan(tmp, "02-pending-area.md", "# Area 02\n")
    addTicketToPlan(tmp, "done", "0001-done-area-summary.md", "# Done\n\n**Area:** 01-done-area\n")
    # Write area hashes matching current content
    var hashes = initTable[string, string]()
    hashes["01-done-area"] = $secureHash("# Area 01\n")
    hashes["02-pending-area"] = $secureHash("# Area 02\n")
    writeAreaHashesInPlan(tmp, hashes)

    let needed = areasNeedingTickets(tmp)
    check needed.len == 0  # both areas have matching hashes, done area not re-triggered

  test "done ticket with changed area content triggers new tickets":
    let tmp = getTempDir() / "scriptorium_test_done_changed_hash"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addAreaToPlan(tmp, "01-done-area.md", "# Area 01 v2\n")  # content differs from stored hash
    addAreaToPlan(tmp, "02-unchanged.md", "# Area 02\n")
    addTicketToPlan(tmp, "done", "0001-done-area-summary.md", "# Done\n\n**Area:** 01-done-area\n")
    # Write area hashes with old content hash for 01-done-area
    var hashes = initTable[string, string]()
    hashes["01-done-area"] = $secureHash("# Area 01 v1\n")  # old hash
    hashes["02-unchanged"] = $secureHash("# Area 02\n")  # matching hash
    writeAreaHashesInPlan(tmp, hashes)

    let needed = areasNeedingTickets(tmp)
    check "areas/01-done-area.md" in needed  # changed content triggers new tickets
    check "areas/02-unchanged.md" notin needed  # unchanged is suppressed

  test "open ticket blocks area even when content changed":
    let tmp = getTempDir() / "scriptorium_test_open_blocks_changed"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addAreaToPlan(tmp, "01-active.md", "# Area 01 v2\n")
    addTicketToPlan(tmp, "open", "0001-active-ticket.md", "# Ticket\n\n**Area:** 01-active\n")
    var hashes = initTable[string, string]()
    hashes["01-active"] = $secureHash("# Area 01 v1\n")  # old hash, content changed
    writeAreaHashesInPlan(tmp, hashes)

    let needed = areasNeedingTickets(tmp)
    check "areas/01-active.md" notin needed  # open ticket blocks regardless of content change

  test "architect creates spec hash marker on first run":
    let tmp = getTempDir() / "scriptorium_test_arch_spec_hash_first_run"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    writeSpecInPlan(tmp, "# Spec\n\nBuild a CLI tool.\n")

    proc generator(model: string, spec: string): seq[AreaDocument] =
      result = @[AreaDocument(path: "01-cli.md", content: "# CLI Area\n")]

    let synced = syncAreasFromSpec(tmp, generator)
    check synced

    let files = planTreeFiles(tmp)
    check "areas/.spec-hash" in files
    let hashContent = readPlanFile(tmp, "areas/.spec-hash").strip()
    check hashContent == $secureHash("# Spec\n\nBuild a CLI tool.\n")

  test "architect skips when spec unchanged":
    let tmp = getTempDir() / "scriptorium_test_arch_skip_unchanged"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    let specContent = "# Spec\n\nBuild a CLI tool.\n"
    writeSpecInPlan(tmp, specContent)
    addAreaToPlan(tmp, "01-cli.md", "# CLI Area\n")
    writeSpecHashInPlan(tmp, $secureHash(specContent))

    var callCount = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      inc callCount
      result = AgentRunResult(backend: harnessClaudeCode, exitCode: 0, attempt: 1, attemptCount: 1)

    let changed = runArchitectAreas(tmp, fakeRunner)
    check not changed
    check callCount == 0  # architect was not invoked

  test "architect re-runs when spec changes":
    let tmp = getTempDir() / "scriptorium_test_arch_rerun_spec_changed"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    let oldSpec = "# Spec\n\nBuild a CLI tool.\n"
    writeSpecInPlan(tmp, "# Spec\n\nBuild a CLI tool with logging.\n")  # new content
    addAreaToPlan(tmp, "01-cli.md", "# CLI Area\n")
    writeSpecHashInPlan(tmp, $secureHash(oldSpec))  # hash of old spec

    var callCount = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      inc callCount
      # Simulate architect writing an updated area
      writeFile(request.workingDir / "areas/02-logging.md", "# Logging Area\n")
      result = AgentRunResult(backend: harnessClaudeCode, exitCode: 0, attempt: 1, attemptCount: 1)

    let changed = runArchitectAreas(tmp, fakeRunner)
    check changed
    check callCount == 1

    let files = planTreeFiles(tmp)
    check "areas/02-logging.md" in files
    check "areas/.spec-hash" in files

  test "migration writes spec hash marker for existing areas without re-running":
    let tmp = getTempDir() / "scriptorium_test_arch_migration"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    let specContent = "# Spec\n\nExisting project.\n"
    writeSpecInPlan(tmp, specContent)
    addAreaToPlan(tmp, "01-cli.md", "# CLI Area\n")
    # No .spec-hash file — simulates pre-upgrade state

    var callCount = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      inc callCount
      result = AgentRunResult(backend: harnessClaudeCode, exitCode: 0, attempt: 1, attemptCount: 1)

    let changed = runArchitectAreas(tmp, fakeRunner)
    check not changed  # migration only, no architect run
    check callCount == 0

    let files = planTreeFiles(tmp)
    check "areas/.spec-hash" in files  # marker was written
    let hashContent = readPlanFile(tmp, "areas/.spec-hash").strip()
    check hashContent == $secureHash(specContent)

  test "runOrchestratorForTicks drives spec to done in one bounded tick with mocked runners":
    let tmp = getTempDir() / "scriptorium_test_v1_39_full_cycle_tick"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nDeliver one full-flow ticket.\n")
    writeOrchestratorEndpointConfig(tmp, 22)
    var cfg = loadConfig(tmp)
    cfg.concurrency.maxAgents = 1
    writeScriptoriumConfig(tmp, cfg)

    var callOrder: seq[string] = @[]
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Emulate architect, manager, and coding agent by ticketId role markers.
      callOrder.add(request.ticketId)
      case request.ticketId
      of "architect-areas":
        writeFile(
          request.workingDir / "areas/01-full-flow.md",
          "# Area 01\n\n## Goal\n- Full flow.\n",
        )
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          lastMessage: "areas done",
          timeoutKind: "none",
        )
      of "manager-01-full-flow":
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          lastMessage: "```markdown\n# Full Flow\n\n**Area:** 01-full-flow\n```",
          timeoutKind: "none",
        )
      of "0001-prediction":
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          lastMessage: """{"predicted_difficulty": "easy", "predicted_duration_minutes": 10, "reasoning": "Simple ticket."}""",
          timeoutKind: "none",
        )
      of "0001":
        writeFile(request.workingDir / "flow-output.txt", "done\n")
        runCmdOrDie("git -C " & quoteShell(request.workingDir) & " add flow-output.txt")
        runCmdOrDie("git -C " & quoteShell(request.workingDir) & " commit -m test-v1-39-flow-output")
        callSubmitPrTool("ship flow")
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          lastMessage: "Done.",
          timeoutKind: "none",
        )
      else:
        raise newException(ValueError, "unexpected runner ticket id: " & request.ticketId)

    runOrchestratorForTicks(tmp, 1, fakeRunner)

    let files = planTreeFiles(tmp)
    check callOrder == @["architect-areas", "manager-01-full-flow", "0001-prediction", "0001"]
    check "areas/01-full-flow.md" in files
    check "tickets/done/0001-full-flow.md" in files
    check "tickets/open/0001-full-flow.md" notin files
    check "tickets/in-progress/0001-full-flow.md" notin files
    check "queue/merge/pending/0001-0001.md" notin files

    let (masterFile, masterRc) = execCmdEx("git -C " & quoteShell(tmp) & " show master:flow-output.txt")
    check masterRc == 0
    check masterFile.strip() == "done"

    validateTicketStateInvariant(tmp)
    validateTransitionCommitInvariant(tmp)

suite "interactive planning":
  test "prompt assembly includes spec, history, and user message":
    let repoPath = "/tmp/repo"
    let spec = "# Spec\n\n- feature A\n"
    let history = @[
      PlanTurn(role: "engineer", text: "add feature B"),
      PlanTurn(role: "architect", text: "Added feature B to spec."),
    ]
    let userMsg = "add feature C"

    let planPath = "/tmp/plan-worktree"
    let prompt = buildInteractivePlanPrompt(repoPath, planPath, spec, history, userMsg)

    check repoPath in prompt
    check planPath in prompt
    check spec.strip() in prompt
    check "add feature B" in prompt
    check "Added feature B to spec." in prompt
    check "add feature C" in prompt
    check "AGENTS.md" in prompt
    check "Active working directory path (this is the scriptorium plan worktree):" in prompt
    check "Only edit spec.md in this working directory." in prompt
    check "Treat `" in prompt
    check "as the authoritative planning file." in prompt
    check "If the engineer is discussing or asking questions, reply directly and do not edit spec.md." in prompt
    check "Only edit spec.md when the engineer asks to change plan content." in prompt
    check "Inline convenience copy of `spec.md` from the plan worktree:" in prompt

  test "turn commits when spec changes":
    let tmp = getTempDir() / "scriptorium_test_interactive_commit"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    var callCount = 0
    var capturedWorkingDir = ""
    var capturedPrompt = ""
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Write new content to spec.md and return a deterministic result.
      inc callCount
      capturedWorkingDir = req.workingDir
      capturedPrompt = req.prompt
      check req.heartbeatIntervalMs > 0
      check not req.onEvent.isNil
      req.onEvent(AgentStreamEvent(kind: agentEventReasoning, text: "reading spec", rawLine: ""))
      req.onEvent(AgentStreamEvent(kind: agentEventTool, text: "read_file (started)", rawLine: ""))
      writeFile(req.workingDir / "spec.md", "# Updated Spec\n\n- new item\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "Updated spec.",
        timeoutKind: "none",
      )

    var msgIdx = 0
    proc fakeInput(): string =
      ## Yield one message then raise EOFError.
      if msgIdx >= 1:
        raise newException(EOFError, "done")
      inc msgIdx
      result = "hello"

    runInteractivePlanSession(tmp, fakeRunner, fakeInput, quiet = true)

    let (logOutput, logRc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " log --oneline scriptorium/plan"
    )
    check logRc == 0
    check "plan session turn 1" in logOutput
    check callCount == 1
    check capturedWorkingDir != tmp
    check tmp in capturedPrompt
    check "AGENTS.md" in capturedPrompt
    check capturedWorkingDir in capturedPrompt

  test "turn makes no commit when spec unchanged":
    let tmp = getTempDir() / "scriptorium_test_interactive_no_commit"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Return a result without modifying spec.md.
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "No changes needed.",
        timeoutKind: "none",
      )

    var msgIdx = 0
    proc fakeInput(): string =
      ## Yield one message then raise EOFError.
      if msgIdx >= 1:
        raise newException(EOFError, "done")
      inc msgIdx
      result = "hello"

    let before = planCommitCount(tmp)
    runInteractivePlanSession(tmp, fakeRunner, fakeInput, quiet = true)
    let after = planCommitCount(tmp)

    check after == before

  test "/show, /help, /quit do not invoke runner":
    let tmp = getTempDir() / "scriptorium_test_interactive_commands"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    var callCount = 0
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Count invocations; should never be called for slash commands.
      inc callCount
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    let cmds = @["/show", "/help", "/quit"]
    var cmdIdx = 0
    proc fakeInput(): string =
      ## Yield slash commands in sequence, then EOF.
      if cmdIdx >= cmds.len:
        raise newException(EOFError, "done")
      result = cmds[cmdIdx]
      inc cmdIdx

    runInteractivePlanSession(tmp, fakeRunner, fakeInput, quiet = true)

    check callCount == 0

  test "turn rejects writes outside spec.md":
    let tmp = getTempDir() / "scriptorium_test_interactive_out_of_scope"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Write one out-of-scope file in the plan worktree.
      writeFile(req.workingDir / "spec.md", "# Updated Spec\n")
      writeFile(req.workingDir / "areas/02-out-of-scope.md", "# Nope\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "done",
        timeoutKind: "none",
      )

    var msgIdx = 0
    proc fakeInput(): string =
      ## Yield one message then raise EOFError.
      if msgIdx >= 1:
        raise newException(EOFError, "done")
      inc msgIdx
      result = "hello"

    let before = planCommitCount(tmp)
    expect ValueError:
      runInteractivePlanSession(tmp, fakeRunner, fakeInput, quiet = true)
    let after = planCommitCount(tmp)
    let files = planTreeFiles(tmp)

    check after == before
    check "areas/02-out-of-scope.md" notin files

  test "interrupt-style input exits session cleanly":
    let tmp = getTempDir() / "scriptorium_test_interactive_interrupt"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    var runnerCalls = 0
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Track runner invocations; interrupted input should stop before agent calls.
      inc runnerCalls
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    var inputCalls = 0
    proc fakeInput(): string =
      ## Simulate interrupted terminal input.
      inc inputCalls
      raise newException(IOError, "interrupted by signal")

    let before = planCommitCount(tmp)
    runInteractivePlanSession(tmp, fakeRunner, fakeInput, quiet = true)
    let after = planCommitCount(tmp)

    check inputCalls == 1
    check runnerCalls == 0
    check after == before

suite "interactive ask session":
  test "ask prompt includes read-only instruction and spec":
    let tmp = getTempDir() / "scriptorium_test_ask_prompt"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    let prompt = buildInteractiveAskPrompt(tmp, tmp, "# My Spec\n", @[], "what is this?")
    check "read-only" in prompt.toLowerAscii()
    check "Do NOT edit any files" in prompt
    check "# My Spec" in prompt
    check "what is this?" in prompt
    check "AGENTS.md" in prompt

  test "ask prompt includes conversation history":
    let tmp = getTempDir() / "scriptorium_test_ask_history"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    let history = @[
      PlanTurn(role: "engineer", text: "hello"),
      PlanTurn(role: "architect", text: "hi there"),
    ]
    let prompt = buildInteractiveAskPrompt(tmp, tmp, "# Spec\n", history, "follow up")
    check "[engineer]: hello" in prompt
    check "[architect]: hi there" in prompt
    check "follow up" in prompt

  test "ask session invokes runner and records history":
    let tmp = getTempDir() / "scriptorium_test_ask_session"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    var callCount = 0
    var capturedPrompt = ""
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Return a response without modifying any files.
      inc callCount
      capturedPrompt = req.prompt
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "The spec describes a CLI tool.",
        timeoutKind: "none",
      )

    var msgIdx = 0
    proc fakeInput(): string =
      ## Yield one message then raise EOFError.
      if msgIdx >= 1:
        raise newException(EOFError, "done")
      inc msgIdx
      result = "what does the spec say?"

    runInteractiveAskSession(tmp, fakeRunner, fakeInput, quiet = true)

    check callCount == 1
    check "what does the spec say?" in capturedPrompt
    check "read-only" in capturedPrompt.toLowerAscii()

  test "ask session makes no commits":
    let tmp = getTempDir() / "scriptorium_test_ask_no_commit"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Return a response without modifying any files.
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "Here is my answer.",
        timeoutKind: "none",
      )

    var msgIdx = 0
    proc fakeInput(): string =
      if msgIdx >= 1:
        raise newException(EOFError, "done")
      inc msgIdx
      result = "tell me about the project"

    let before = planCommitCount(tmp)
    runInteractiveAskSession(tmp, fakeRunner, fakeInput, quiet = true)
    let after = planCommitCount(tmp)

    check after == before

  test "ask session rejects writes":
    let tmp = getTempDir() / "scriptorium_test_ask_rejects_writes"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      ## Attempt to write a file, which should be rejected.
      writeFile(req.workingDir / "spec.md", "# Modified Spec\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "I edited the spec.",
        timeoutKind: "none",
      )

    var msgIdx = 0
    proc fakeInput(): string =
      if msgIdx >= 1:
        raise newException(EOFError, "done")
      inc msgIdx
      result = "tell me something"

    let before = planCommitCount(tmp)
    expect ValueError:
      runInteractiveAskSession(tmp, fakeRunner, fakeInput, quiet = true)
    let after = planCommitCount(tmp)
    check after == before

  test "/show, /help, /quit do not invoke runner in ask mode":
    let tmp = getTempDir() / "scriptorium_test_ask_commands"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)

    var callCount = 0
    proc fakeRunner(req: AgentRunRequest): AgentRunResult =
      inc callCount
      discard req
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "",
        timeoutKind: "none",
      )

    let cmds = @["/show", "/help", "/quit"]
    var cmdIdx = 0
    proc fakeInput(): string =
      if cmdIdx >= cmds.len:
        raise newException(EOFError, "done")
      result = cmds[cmdIdx]
      inc cmdIdx

    runInteractiveAskSession(tmp, fakeRunner, fakeInput, quiet = true)

    check callCount == 0

suite "orchestrator agent enqueue with fakes":
  test "agent run enqueues exactly one merge request with metadata":
    withTempRepo("scriptorium_test_enqueue_metadata_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addPassingMakefile(repoPath)
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")

      let assignment = assignOldestOpenTicket(repoPath)
      proc fakeRunner(request: AgentRunRequest): AgentRunResult =
        ## Return a deterministic run output and signal submit_pr through MCP.
        discard request
        callSubmitPrTool("ship it")
        result = AgentRunResult(
          backend: harnessCodex,
          command: @["codex", "exec"],
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          stdout: "",
          logFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.jsonl",
          lastMessageFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.last_message.txt",
          lastMessage: "Done.",
          timeoutKind: "none",
        )

      discard executeAssignedTicket(repoPath, assignment, fakeRunner)

      let queueFiles = pendingQueueFiles(repoPath)
      check queueFiles.len == 1
      check queueFiles[0] == "queue/merge/pending/0001-0001.md"

      let queueEntry = readPlanFile(repoPath, queueFiles[0])
      check "**Ticket:** tickets/in-progress/0001-first.md" in queueEntry
      check "**Ticket ID:** 0001" in queueEntry
      check "**Summary:** ship it" in queueEntry
      check "**Branch:** scriptorium/ticket-0001" in queueEntry
      check ("**Worktree:** " & assignment.worktree) in queueEntry
    )

  test "orchestrator tick assigns and executes before merge queue processing":
    withTempRepo("scriptorium_test_tick_assign_execute_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addPassingMakefile(repoPath)
      writeSpecInPlan(repoPath, "# Spec\n\nDrive orchestrator tick.\n")
      addTicketToPlan(repoPath, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
      addTicketToPlan(repoPath, "open", "0002-second.md", "# Ticket 2\n\n**Area:** b\n")

      let firstAssignment = assignOldestOpenTicket(repoPath)
      writeFile(firstAssignment.worktree / "ticket-output.txt", "done\n")
      runCmdOrDie("git -C " & quoteShell(firstAssignment.worktree) & " add ticket-output.txt")
      runCmdOrDie("git -C " & quoteShell(firstAssignment.worktree) & " commit -m ticket-output")
      discard enqueueMergeRequest(repoPath, firstAssignment, "first summary")

      let fakeBinDir = createTempDir("scriptorium_test_fake_codex_", "", getTempDir())
      defer:
        removeDir(fakeBinDir)
      let fakeCodexPath = fakeBinDir / "codex"
      let fakeScript = "#!/usr/bin/env bash\n" &
        "set -euo pipefail\n" &
        "last_message=\"\"\n" &
        "while [[ $# -gt 0 ]]; do\n" &
        "  case \"$1\" in\n" &
        "    --output-last-message) last_message=\"$2\"; shift 2 ;;\n" &
        "    *) shift ;;\n" &
        "  esac\n" &
        "done\n" &
        "cat >/dev/null\n" &
        "printf '{\"type\":\"message\",\"text\":\"ok\"}\\n'\n" &
        "printf 'done\\n' > \"$last_message\"\n"
      writeFile(fakeCodexPath, fakeScript)
      setFilePermissions(fakeCodexPath, {fpUserRead, fpUserWrite, fpUserExec})

      let oldPath = getEnv("PATH", "")
      putEnv("PATH", fakeBinDir & ":" & oldPath)
      defer:
        putEnv("PATH", oldPath)

      writeOrchestratorEndpointConfig(repoPath, 0)
      runOrchestratorForTicks(repoPath, 1)

      let files = planTreeFiles(repoPath)
      check "tickets/done/0001-first.md" in files
      check "tickets/open/0002-second.md" in files
      check pendingQueueFiles(repoPath).len == 0

      let commits = latestPlanCommits(repoPath, 20)
      check commits.anyIt(it == "scriptorium: complete ticket 0001")
      check commits.anyIt(it == "scriptorium: review ticket 0001")
      check commits.anyIt(it.startsWith("scriptorium: reopen failed ticket"))
      check commits.anyIt(it == "scriptorium: record agent run 0002-second")
      check commits.anyIt(it == "scriptorium: assign ticket 0002-second")
    )

  test "end-to-end happy path from spec to done":
    withTempRepo("scriptorium_test_e2e_happy_path_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addPassingMakefile(repoPath)

      var architectCalls = 0
      proc architectGenerator(model: string, spec: string): seq[AreaDocument] =
        ## Return one deterministic area document from spec input.
        inc architectCalls
        check model == "claude-opus-4-6"
        check "scriptorium plan" in spec
        result = @[
          AreaDocument(
            path: "01-e2e.md",
            content: "# Area 01\n\n## Goal\n- Validate V1 happy path.\n",
          )
        ]

      let syncedAreas = syncAreasFromSpec(repoPath, architectGenerator)
      check syncedAreas
      check architectCalls == 1

      addTicketToPlan(repoPath, "open", "0001-e2e-happy-path.md",
        "# Ticket 1\n\nImplement end-to-end flow.\n\n**Area:** 01-e2e\n")

      let filesAfterPlanning = planTreeFiles(repoPath)
      check "areas/01-e2e.md" in filesAfterPlanning
      check "tickets/open/0001-e2e-happy-path.md" in filesAfterPlanning

      let assignment = assignOldestOpenTicket(repoPath)
      check assignment.inProgressTicket == "tickets/in-progress/0001-e2e-happy-path.md"
      writeFile(assignment.worktree / "e2e-output.txt", "done\n")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " add e2e-output.txt")
      runCmdOrDie("git -C " & quoteShell(assignment.worktree) & " commit -m test-e2e-ticket-output")
      let (ticketHead, ticketHeadRc) = execCmdEx("git -C " & quoteShell(assignment.worktree) & " rev-parse HEAD")
      doAssert ticketHeadRc == 0

      proc fakeRunner(request: AgentRunRequest): AgentRunResult =
        ## Return a deterministic successful output and request merge submission.
        discard request
        callSubmitPrTool("ship e2e")
        result = AgentRunResult(
          backend: harnessCodex,
          command: @["codex", "exec"],
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          stdout: "",
          logFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.jsonl",
          lastMessageFile: assignment.worktree / ".scriptorium/logs/0001/attempt-01.last_message.txt",
          lastMessage: "Done.",
          timeoutKind: "none",
        )

      discard executeAssignedTicket(repoPath, assignment, fakeRunner)
      let pending = pendingQueueFiles(repoPath)
      check pending.len == 1
      check pending[0] == "queue/merge/pending/0001-0001.md"

      let processed = processMergeQueue(repoPath, noopRunner)
      check processed
      check pendingQueueFiles(repoPath).len == 0

      let finalFiles = planTreeFiles(repoPath)
      check "tickets/done/0001-e2e-happy-path.md" in finalFiles
      check "tickets/open/0001-e2e-happy-path.md" notin finalFiles
      check "tickets/in-progress/0001-e2e-happy-path.md" notin finalFiles

      let (masterOutput, masterRc) = execCmdEx("git -C " & quoteShell(repoPath) & " show master:e2e-output.txt")
      check masterRc == 0
      check masterOutput.strip() == "done"

      let (_, ancestorRc) = execCmdEx(
        "git -C " & quoteShell(repoPath) & " merge-base --is-ancestor " & ticketHead.strip() & " master"
      )
      check ancestorRc == 0

      validateTicketStateInvariant(repoPath)
      validateTransitionCommitInvariant(repoPath)
    )

  test "one-shot plan runner reads repo path context and commits spec only":
    withTempRepo("scriptorium_test_oneshot_plan_runner_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      writeFile(repoPath / "source-marker.txt", "integration-marker\n")
      runCmdOrDie("git -C " & quoteShell(repoPath) & " add source-marker.txt")
      runCmdOrDie("git -C " & quoteShell(repoPath) & " commit -m test-add-source-marker")

      var callCount = 0
      var capturedPrompt = ""
      var capturedRepoPath = ""
      proc fakeRunner(request: AgentRunRequest): AgentRunResult =
        ## Read the repo path from prompt context and update spec.md in plan worktree.
        inc callCount
        capturedPrompt = request.prompt
        let repoPathMarker = "Project repository root path (read project source files and instructions from here):\n"
        let markerIndex = request.prompt.find(repoPathMarker)
        doAssert markerIndex >= 0
        let pathStart = markerIndex + repoPathMarker.len
        let pathEnd = request.prompt.find('\n', pathStart)
        doAssert pathEnd > pathStart
        let repoPathFromPrompt = request.prompt[pathStart..<pathEnd].strip()
        capturedRepoPath = repoPathFromPrompt
        let marker = readFile(repoPathFromPrompt / "source-marker.txt").strip()
        writeFile(request.workingDir / "spec.md", "# Integration Spec\n\n- marker: " & marker & "\n")

        result = AgentRunResult(
          backend: harnessCodex,
          command: @["codex", "exec"],
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          stdout: "",
          logFile: request.workingDir / ".scriptorium/logs/plan-spec/attempt-01.jsonl",
          lastMessageFile: request.workingDir / ".scriptorium/logs/plan-spec/attempt-01.last_message.txt",
          lastMessage: "Updated spec",
          timeoutKind: "none",
        )

      let changed = updateSpecFromArchitect(repoPath, "sync source marker", fakeRunner)

      check changed
      check callCount == 1
      check capturedRepoPath == repoPath
      check "AGENTS.md" in capturedPrompt
      check "Active working directory path (this is the scriptorium plan worktree):" in capturedPrompt
      check "Only edit spec.md in this working directory." in capturedPrompt
      check "as the authoritative planning file." in capturedPrompt
      check "Inline convenience copy of `spec.md` from the plan worktree:" in capturedPrompt

      let specBody = readPlanFile(repoPath, "spec.md")
      check "# Integration Spec" in specBody
      check "- marker: integration-marker" in specBody

      let files = planTreeFiles(repoPath)
      check "spec.md" in files
      check "areas/01-out-of-scope.md" notin files

      let commits = latestPlanCommits(repoPath, 1)
      check commits.len == 1
      check commits[0] == "scriptorium: update spec from architect"
    )

suite "logging":
  test "initLog creates directory and file":
    let tmpDir = createTempDir("scriptorium_log_test_", "")
    defer: removeDir(tmpDir)
    let fakeRepo = tmpDir / "myproject"
    createDir(fakeRepo)
    initLog(fakeRepo)
    defer: closeLog()
    check logFilePath.len > 0
    check fileExists(logFilePath)
    check ".scriptorium/logs/orchestrator/" in logFilePath
    check "run_" in logFilePath

  test "logInfo writes timestamped line to file":
    let tmpDir = createTempDir("scriptorium_log_test_", "")
    defer: removeDir(tmpDir)
    let fakeRepo = tmpDir / "testproj"
    createDir(fakeRepo)
    initLog(fakeRepo)
    logInfo("hello from test")
    closeLog()
    let content = readFile(logFilePath)
    check "[INFO]" in content
    check "hello from test" in content

  test "log levels write correct labels":
    let tmpDir = createTempDir("scriptorium_log_test_", "")
    defer: removeDir(tmpDir)
    let fakeRepo = tmpDir / "leveltest"
    createDir(fakeRepo)
    initLog(fakeRepo)
    logDebug("dbg msg")
    logWarn("wrn msg")
    logError("err msg")
    closeLog()
    let content = readFile(logFilePath)
    check "[DEBUG] dbg msg" in content
    check "[WARN] wrn msg" in content
    check "[ERROR] err msg" in content

  test "log without initLog does not crash":
    closeLog()
    logInfo("should just echo, not crash")

  test "executeAssignedTicket reopens ticket when agent does not call submit_pr":
    let tmp = getTempDir() / "scriptorium_test_reopen_failed"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0032-fail.md", "# Ticket 32\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 900)

    let assignment = assignOldestOpenTicket(tmp)
    let before = planCommitCount(tmp)

    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Simulate an agent that exits 137 without calling submit_pr.
      discard request
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 137,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        lastMessage: "",
        timeoutKind: "hard",
      )

    let runResult = executeAssignedTicket(tmp, assignment, fakeRunner)
    check runResult.exitCode == 137

    let after = planCommitCount(tmp)
    check after == before + 4

    let files = planTreeFiles(tmp)
    check "tickets/open/0032-fail.md" in files
    check "tickets/in-progress/0032-fail.md" notin files

    let commits = latestPlanCommits(tmp, 2)
    check commits[1].startsWith("scriptorium: reopen failed ticket")

  test "executeAssignedTicket retries stalled agent with continuation prompt":
    let tmp = getTempDir() / "scriptorium_test_stall_retry"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0033-stall.md", "# Ticket 33\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 902)

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "Makefile", "test:\n\t@echo OK\nintegration-test:\n\t@echo OK\n")

    var callCount = 0
    var capturedRequests: seq[AgentRunRequest]
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Return stall on first call, then call submit_pr on second call.
      inc callCount
      capturedRequests.add(request)
      if callCount == 2:
        callSubmitPrTool("stall retry done")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: callCount,
        attemptCount: 1,
        stdout: "",
        lastMessage: "done",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunner)

    check callCount == 2
    check capturedRequests.len == 2
    let firstPrompt = capturedRequests[0].prompt
    let retryPrompt = capturedRequests[1].prompt
    check "Ticket 33" in firstPrompt
    check "stall retry" in retryPrompt.toLower
    check "Ticket 33" in retryPrompt
    check "submit_pr" in retryPrompt

  test "executeAssignedTicket stops stall retries after maxAttempts":
    let tmp = getTempDir() / "scriptorium_test_stall_exhausted"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0034-stall.md", "# Ticket 34\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 903)

    let assignment = assignOldestOpenTicket(tmp)
    let before = planCommitCount(tmp)

    var callCount = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Always stall: exit cleanly without calling submit_pr.
      discard request
      inc callCount
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: callCount,
        attemptCount: 1,
        stdout: "",
        lastMessage: "",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunner)
    let after = planCommitCount(tmp)

    check callCount == 2
    let files = planTreeFiles(tmp)
    check "tickets/open/0034-stall.md" in files
    check "tickets/in-progress/0034-stall.md" notin files
    let commits = latestPlanCommits(tmp, 2)
    check commits[1].startsWith("scriptorium: reopen failed ticket")
    check after == before + 5

  test "executeAssignedTicket includes passing test status in stall continuation prompt":
    let tmp = getTempDir() / "scriptorium_test_stall_testpass"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0035-stall.md", "# Ticket 35\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 904)

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "Makefile", "test:\n\t@echo PASS\nintegration-test:\n\t@echo PASS\n")

    var callCount = 0
    var capturedRequests: seq[AgentRunRequest]
    proc fakeRunnerPass(request: AgentRunRequest): AgentRunResult =
      ## Stall on first call, then submit_pr on second.
      inc callCount
      capturedRequests.add(request)
      if callCount == 2:
        callSubmitPrTool("test pass retry done")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: callCount,
        attemptCount: 1,
        stdout: "",
        lastMessage: "done",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunnerPass)

    check callCount == 2
    check capturedRequests.len == 2
    let retryPrompt = capturedRequests[1].prompt
    check "tests are passing" in retryPrompt.toLower
    check "submit_pr" in retryPrompt

  test "executeAssignedTicket includes failing test output in stall continuation prompt":
    let tmp = getTempDir() / "scriptorium_test_stall_testfail"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0036-stall.md", "# Ticket 36\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 905)

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "Makefile", "test:\n\t@echo FAILURE OUTPUT\n\t@false\nintegration-test:\n\t@echo OK\n")

    var callCount = 0
    var capturedRequests: seq[AgentRunRequest]
    proc fakeRunnerFail(request: AgentRunRequest): AgentRunResult =
      ## Stall on first call, then submit_pr on second.
      inc callCount
      capturedRequests.add(request)
      if callCount == 2:
        callSubmitPrTool("test fail retry done")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: callCount,
        attemptCount: 1,
        stdout: "",
        lastMessage: "done",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunnerFail)

    check callCount == 2
    check capturedRequests.len == 2
    let retryPrompt = capturedRequests[1].prompt
    check "tests are failing" in retryPrompt.toLower
    check "FAILURE OUTPUT" in retryPrompt
    check "fix the failing tests" in retryPrompt.toLower

  test "executeAssignedTicket accumulates test wall time on stall":
    let tmp = getTempDir() / "scriptorium_test_stall_testwall"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0037-testwall.md", "# Ticket 37\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 906)

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "Makefile", "test:\n\t@echo OK\nintegration-test:\n\t@echo OK\n")

    let ticketId = "0037"

    var callCount = 0
    proc fakeRunnerStall(request: AgentRunRequest): AgentRunResult =
      ## Stall on first call, then submit_pr on second.
      inc callCount
      if callCount == 2:
        callSubmitPrTool("testwall done")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: callCount,
        attemptCount: 1,
        stdout: "",
        lastMessage: "done",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunnerStall)

    check callCount == 2
    check ticketTestWalls.hasKey(ticketId)
    check ticketTestWalls[ticketId] > 0.0
    check ticketCodingWalls.hasKey(ticketId)
    check ticketCodingWalls[ticketId] >= 0.0
    check ticketStartTimes.hasKey(ticketId)

  test "executeAssignedTicket cleans up timing state on reopen":
    let tmp = getTempDir() / "scriptorium_test_timing_cleanup"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0038-cleanup.md", "# Ticket 38\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 907)

    let assignment = assignOldestOpenTicket(tmp)
    let ticketId = "0038"

    check ticketStartTimes.hasKey(ticketId)
    check ticketCodingWalls.hasKey(ticketId)
    check ticketTestWalls.hasKey(ticketId)

    proc fakeRunnerFail(request: AgentRunRequest): AgentRunResult =
      ## Exit non-zero without submit_pr to trigger reopen.
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 1,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        lastMessage: "",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunnerFail)

    check not ticketStartTimes.hasKey(ticketId)
    check not ticketAttemptCounts.hasKey(ticketId)
    check not ticketCodingWalls.hasKey(ticketId)
    check not ticketTestWalls.hasKey(ticketId)

  test "reassigned ticket gets a fresh worktree branch without stale commits":
    let tmp = getTempDir() / "scriptorium_test_fresh_worktree"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0050-stale.md", "# Ticket 50\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 901)

    let assignment1 = assignOldestOpenTicket(tmp)

    proc fakeRunnerFirst(request: AgentRunRequest): AgentRunResult =
      ## Write a stale file and commit it, then exit non-zero without submit_pr.
      writeFile(request.workingDir / "stale.txt", "should not survive")
      discard execCmdEx("git -C " & quoteShell(request.workingDir) & " add stale.txt")
      discard execCmdEx("git -C " & quoteShell(request.workingDir) & " commit -m stale-commit")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 1,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        lastMessage: "",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment1, fakeRunnerFirst)

    let assignment2 = assignOldestOpenTicket(tmp)
    check assignment2.inProgressTicket.len > 0

    let (logOutput, logRc) = execCmdEx(
      "git -C " & quoteShell(assignment2.worktree) & " log --oneline"
    )
    check logRc == 0
    check "stale-commit" notin logOutput
    check not fileExists(assignment2.worktree / "stale.txt")

    discard execCmdEx("git -C " & quoteShell(tmp) & " worktree remove --force " & quoteShell(assignment2.worktree))

suite "formatDuration":
  test "seconds only":
    check formatDuration(0.0) == "0s"
    check formatDuration(5.0) == "5s"
    check formatDuration(59.9) == "59s"

  test "minutes and seconds":
    check formatDuration(60.0) == "1m0s"
    check formatDuration(192.0) == "3m12s"
    check formatDuration(3599.0) == "59m59s"

  test "hours and minutes":
    check formatDuration(3600.0) == "1h0m"
    check formatDuration(4980.0) == "1h23m"
    check formatDuration(7200.0) == "2h0m"

suite "parseMetricField":
  const
    SampleTicket = "# Ticket\n\n**Area:** a\n\n## Metrics\n- wall_time_seconds: 120\n- outcome: done\n- attempt_count: 1\n- model: opus\n\n## Post-Analysis\n- actual_difficulty: easy\n"

  test "extracts wall_time_seconds from metrics section":
    check parseMetricField(SampleTicket, "wall_time_seconds") == "120"

  test "extracts outcome from metrics section":
    check parseMetricField(SampleTicket, "outcome") == "done"

  test "extracts attempt_count from metrics section":
    check parseMetricField(SampleTicket, "attempt_count") == "1"

  test "returns empty string when field missing":
    check parseMetricField(SampleTicket, "nonexistent") == ""

  test "returns empty string when no metrics section":
    check parseMetricField("# Ticket\n\nNo metrics here.\n", "outcome") == ""

  test "stops at next section":
    check parseMetricField(SampleTicket, "actual_difficulty") == ""

suite "session summary":
  test "logSessionSummary writes two INFO lines with session stats":
    let tmpDir = createTempDir("scriptorium_session_summary_", "")
    defer: removeDir(tmpDir)
    let fakeRepo = tmpDir / "summarytest"
    createDir(fakeRepo)
    initLog(fakeRepo)

    resetSessionStats()
    sessionStats.totalTicks = 47
    sessionStats.ticketsCompleted = 3
    sessionStats.ticketsReopened = 1
    sessionStats.ticketsParked = 0
    sessionStats.mergeQueueProcessed = 3
    sessionStats.firstAttemptSuccessCount = 2
    sessionStats.completedTicketWalls = @[312.0, 280.0, 345.0]
    sessionStats.completedCodingWalls = @[242.0, 220.0, 265.0]
    sessionStats.completedTestWalls = @[38.0, 42.0, 34.0]
    logSessionSummary()
    closeLog()

    let content = readFile(logFilePath)
    check "session summary: uptime=" in content
    check "ticks=47" in content
    check "tickets_completed=3" in content
    check "tickets_reopened=1" in content
    check "tickets_parked=0" in content
    check "merge_queue_processed=3" in content
    check "session summary: avg_ticket_wall=" in content
    check "avg_coding_wall=" in content
    check "avg_test_wall=" in content
    check "first_attempt_success=66%" in content

  test "logSessionSummary shows n/a when no tickets completed":
    let tmpDir = createTempDir("scriptorium_session_summary_empty_", "")
    defer: removeDir(tmpDir)
    let fakeRepo = tmpDir / "emptytest"
    createDir(fakeRepo)
    initLog(fakeRepo)

    resetSessionStats()
    sessionStats.totalTicks = 5
    logSessionSummary()
    closeLog()

    let content = readFile(logFilePath)
    check "ticks=5" in content
    check "tickets_completed=0" in content
    check "avg_ticket_wall=n/a" in content
    check "avg_coding_wall=n/a" in content
    check "avg_test_wall=n/a" in content
    check "first_attempt_success=0" in content

suite "per-ticket metrics":
  setup:
    ticketStartTimes.clear()
    ticketAttemptCounts.clear()
    ticketCodingWalls.clear()
    ticketTestWalls.clear()
    ticketModels.clear()
    ticketStdoutBytes.clear()

  test "formatMetricsNote includes all required fields for done outcome":
    let ticketId = "0042"
    ticketStartTimes[ticketId] = epochTime() - 120.0
    ticketAttemptCounts[ticketId] = 2
    ticketCodingWalls[ticketId] = 95.0
    ticketTestWalls[ticketId] = 20.0
    ticketModels[ticketId] = "claude-sonnet-4-20250514"
    ticketStdoutBytes[ticketId] = 8192

    let note = formatMetricsNote(ticketId, "done", "")
    check "## Metrics" in note
    check "- wall_time_seconds: 1" in note
    check "- coding_wall_seconds: 95" in note
    check "- test_wall_seconds: 20" in note
    check "- attempt_count: 2" in note
    check "- outcome: done" in note
    check "- failure_reason: " in note
    check "- model: claude-sonnet-4-20250514" in note
    check "- stdout_bytes: 8192" in note

  test "formatMetricsNote includes failure_reason for reopened outcome":
    let ticketId = "0043"
    ticketStartTimes[ticketId] = epochTime() - 60.0
    ticketAttemptCounts[ticketId] = 1
    ticketCodingWalls[ticketId] = 50.0
    ticketTestWalls[ticketId] = 5.0
    ticketModels[ticketId] = "test-model"
    ticketStdoutBytes[ticketId] = 1024

    let note = formatMetricsNote(ticketId, "reopened", "stall")
    check "- outcome: reopened" in note
    check "- failure_reason: stall" in note

  test "formatMetricsNote includes failure_reason for parked outcome":
    let ticketId = "0044"
    ticketStartTimes[ticketId] = epochTime() - 300.0
    ticketAttemptCounts[ticketId] = 3
    ticketCodingWalls[ticketId] = 200.0
    ticketTestWalls[ticketId] = 80.0
    ticketModels[ticketId] = "test-model"
    ticketStdoutBytes[ticketId] = 4096

    let note = formatMetricsNote(ticketId, "parked", "parked")
    check "- outcome: parked" in note
    check "- failure_reason: parked" in note

  test "appendMetricsNote appends metrics section to ticket content":
    let ticketId = "0045"
    ticketStartTimes[ticketId] = epochTime() - 30.0
    ticketAttemptCounts[ticketId] = 1
    ticketCodingWalls[ticketId] = 25.0
    ticketTestWalls[ticketId] = 3.0
    ticketModels[ticketId] = "test-model"
    ticketStdoutBytes[ticketId] = 512

    let content = "# Test Ticket\n\nSome description."
    let updated = appendMetricsNote(content, ticketId, "done", "")
    check updated.startsWith("# Test Ticket")
    check "## Metrics" in updated
    check "- outcome: done" in updated

  test "cleanupTicketTimings removes all state for a ticket":
    let ticketId = "0046"
    ticketStartTimes[ticketId] = epochTime()
    ticketAttemptCounts[ticketId] = 1
    ticketCodingWalls[ticketId] = 10.0
    ticketTestWalls[ticketId] = 5.0
    ticketModels[ticketId] = "test-model"
    ticketStdoutBytes[ticketId] = 100

    cleanupTicketTimings(ticketId)
    check ticketId notin ticketStartTimes
    check ticketId notin ticketAttemptCounts
    check ticketId notin ticketCodingWalls
    check ticketId notin ticketTestWalls
    check ticketId notin ticketModels
    check ticketId notin ticketStdoutBytes

  test "formatMetricsNote uses defaults for missing ticket state":
    let ticketId = "0047"
    let note = formatMetricsNote(ticketId, "reopened", "timeout_hard")
    check "- wall_time_seconds: 0" in note
    check "- coding_wall_seconds: 0" in note
    check "- test_wall_seconds: 0" in note
    check "- attempt_count: 0" in note
    check "- model: unknown" in note
    check "- stdout_bytes: 0" in note
    check "- failure_reason: timeout_hard" in note

suite "ticket difficulty prediction":
  test "parsePredictionResponse parses valid JSON":
    let response = """{"predicted_difficulty": "medium", "predicted_duration_minutes": 30, "reasoning": "Moderate complexity."}"""
    let prediction = parsePredictionResponse(response)
    check prediction.difficulty == "medium"
    check prediction.durationMinutes == 30
    check prediction.reasoning == "Moderate complexity."

  test "parsePredictionResponse handles JSON with surrounding text":
    let response = "Here is my assessment:\n{\"predicted_difficulty\": \"easy\", \"predicted_duration_minutes\": 10, \"reasoning\": \"Simple change.\"}\nDone."
    let prediction = parsePredictionResponse(response)
    check prediction.difficulty == "easy"
    check prediction.durationMinutes == 10

  test "parsePredictionResponse rejects invalid difficulty":
    expect(ValueError):
      discard parsePredictionResponse("""{"predicted_difficulty": "impossible", "predicted_duration_minutes": 5, "reasoning": "test"}""")

  test "parsePredictionResponse rejects missing JSON":
    expect(ValueError):
      discard parsePredictionResponse("no json here")

  test "formatPredictionNote produces expected markdown":
    let prediction = TicketPrediction(
      difficulty: "hard",
      durationMinutes: 45,
      reasoning: "Multiple modules need changes.",
    )
    let note = formatPredictionNote(prediction)
    check "## Prediction" in note
    check "- predicted_difficulty: hard" in note
    check "- predicted_duration_minutes: 45" in note
    check "- reasoning: Multiple modules need changes." in note

  test "appendPredictionNote appends prediction section to ticket content":
    let content = "# Test Ticket\n\nSome description."
    let prediction = TicketPrediction(
      difficulty: "trivial",
      durationMinutes: 5,
      reasoning: "Simple fix.",
    )
    let updated = appendPredictionNote(content, prediction)
    check updated.startsWith("# Test Ticket")
    check "## Prediction" in updated
    check "- predicted_difficulty: trivial" in updated

  test "buildPredictionPrompt renders template with all placeholders":
    let prompt = buildPredictionPrompt("ticket body", "area body", "spec summary")
    check "ticket body" in prompt
    check "area body" in prompt
    check "spec summary" in prompt

  test "parsePredictionFromContent extracts prediction fields":
    let content = "# Ticket\n\n## Prediction\n- predicted_difficulty: medium\n- predicted_duration_minutes: 30\n- reasoning: Moderate.\n"
    let prediction = parsePredictionFromContent(content)
    check prediction.found == true
    check prediction.difficulty == "medium"
    check prediction.durationMinutes == 30

  test "parsePredictionFromContent returns not found when no prediction section":
    let content = "# Ticket\n\nSome description.\n"
    let prediction = parsePredictionFromContent(content)
    check prediction.found == false

  test "parsePredictionFromContent stops at next section":
    let content = "# Ticket\n\n## Prediction\n- predicted_difficulty: easy\n- predicted_duration_minutes: 10\n\n## Metrics\n- wall_time_seconds: 100\n"
    let prediction = parsePredictionFromContent(content)
    check prediction.found == true
    check prediction.difficulty == "easy"
    check prediction.durationMinutes == 10

  test "classifyActualDifficulty returns trivial for quick single attempt done":
    check classifyActualDifficulty(1, "done", 120) == "trivial"

  test "classifyActualDifficulty returns easy for moderate single attempt done":
    check classifyActualDifficulty(1, "done", 600) == "easy"

  test "classifyActualDifficulty returns medium for long single attempt done":
    check classifyActualDifficulty(1, "done", 1200) == "medium"

  test "classifyActualDifficulty returns hard for two attempt done":
    check classifyActualDifficulty(2, "done", 600) == "hard"

  test "classifyActualDifficulty returns complex for many attempts done":
    check classifyActualDifficulty(3, "done", 600) == "complex"

  test "classifyActualDifficulty returns hard for reopened with few attempts":
    check classifyActualDifficulty(1, "reopened", 300) == "hard"

  test "classifyActualDifficulty returns complex for reopened with many attempts":
    check classifyActualDifficulty(3, "reopened", 300) == "complex"

  test "classifyActualDifficulty returns complex for parked":
    check classifyActualDifficulty(1, "parked", 100) == "complex"

  test "compareDifficulty returns accurate for matching levels":
    check compareDifficulty("medium", "medium") == "accurate"

  test "compareDifficulty returns underestimated when predicted easier":
    check compareDifficulty("easy", "hard") == "underestimated"

  test "compareDifficulty returns overestimated when predicted harder":
    check compareDifficulty("complex", "easy") == "overestimated"

  test "formatPostAnalysisNote produces expected markdown":
    let note = formatPostAnalysisNote("medium", "accurate", "Predicted medium, actual was medium.")
    check "## Post-Analysis" in note
    check "- actual_difficulty: medium" in note
    check "- prediction_accuracy: accurate" in note
    check "- brief_summary: Predicted medium, actual was medium." in note

  test "appendPostAnalysisNote appends post-analysis section":
    let content = "# Ticket\n\nDescription."
    let updated = appendPostAnalysisNote(content, "hard", "underestimated", "Was harder than expected.")
    check updated.startsWith("# Ticket")
    check "## Post-Analysis" in updated
    check "- actual_difficulty: hard" in updated

  test "runPostAnalysis generates full analysis for ticket with prediction":
    let content = "# Ticket\n\n## Prediction\n- predicted_difficulty: easy\n- predicted_duration_minutes: 10\n- reasoning: Simple.\n\n## Metrics\n- wall_time_seconds: 1200\n- attempt_count: 2\n- outcome: done\n"
    let updated = runPostAnalysis(content, "0050", "done", 2, 1200)
    check "## Post-Analysis" in updated
    check "- actual_difficulty: hard" in updated
    check "- prediction_accuracy: underestimated" in updated
    check "- brief_summary:" in updated

  test "runPostAnalysis skips when no prediction section":
    let content = "# Ticket\n\nNo prediction here.\n"
    let updated = runPostAnalysis(content, "0051", "done", 1, 100)
    check "## Post-Analysis" notin updated
    check updated == content

  test "runTicketPrediction appends prediction to ticket markdown":
    withTempRepo("scriptorium_test_prediction_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addTicketToPlan(repoPath, "in-progress", "0099-pred.md",
        "# Predict Me\n\n**Area:** test-area\n\n**Worktree:** /tmp/fake\n")

      proc predictionRunner(request: AgentRunRequest): AgentRunResult =
        ## Return a fake prediction response.
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          lastMessage: """{"predicted_difficulty": "easy", "predicted_duration_minutes": 15, "reasoning": "Small isolated change."}""",
          timeoutKind: "none",
        )

      runTicketPrediction(repoPath, "tickets/in-progress/0099-pred.md", predictionRunner)

      let (ticketContent, rc) = execCmdEx(
        "git -C " & quoteShell(repoPath) & " show scriptorium/plan:tickets/in-progress/0099-pred.md"
      )
      check rc == 0
      check "## Prediction" in ticketContent
      check "- predicted_difficulty: easy" in ticketContent
      check "- predicted_duration_minutes: 15" in ticketContent
    )

  test "runTicketPrediction logs warning and continues on failure":
    withTempRepo("scriptorium_test_prediction_fail_", proc(repoPath: string) =
      runInit(repoPath, quiet = true)
      addTicketToPlan(repoPath, "in-progress", "0098-predfail.md",
        "# Predict Fail\n\n**Area:** test-area\n\n**Worktree:** /tmp/fake\n")

      proc failRunner(request: AgentRunRequest): AgentRunResult =
        ## Return a failing result to test best-effort behavior.
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 1,
          attempt: 1,
          attemptCount: 1,
          lastMessage: "",
          timeoutKind: "none",
        )

      # Should not raise - prediction is best-effort.
      runTicketPrediction(repoPath, "tickets/in-progress/0098-predfail.md", failRunner)

      let (ticketContent, rc) = execCmdEx(
        "git -C " & quoteShell(repoPath) & " show scriptorium/plan:tickets/in-progress/0098-predfail.md"
      )
      check rc == 0
      check "## Prediction" notin ticketContent
    )

suite "health cache persistence":
  test "readHealthCache returns empty table when file does not exist":
    let tmp = getTempDir() / "scriptorium_test_health_cache_empty"
    createDir(tmp)
    defer: removeDir(tmp)

    let cache = readHealthCache(tmp)
    check cache.len == 0

  test "writeHealthCache creates directory and file then readHealthCache round-trips":
    let tmp = getTempDir() / "scriptorium_test_health_cache_roundtrip"
    createDir(tmp)
    defer: removeDir(tmp)

    var cache = initTable[string, HealthCacheEntry]()
    cache["abc123"] = HealthCacheEntry(
      healthy: true,
      timestamp: "2026-03-13T12:00:00Z",
      test_exit_code: 0,
      integration_test_exit_code: 0,
      test_wall_seconds: 45,
      integration_test_wall_seconds: 120,
    )
    cache["def456"] = HealthCacheEntry(
      healthy: false,
      timestamp: "2026-03-13T13:00:00Z",
      test_exit_code: 1,
      integration_test_exit_code: 0,
      test_wall_seconds: 10,
      integration_test_wall_seconds: 0,
    )

    writeHealthCache(tmp, cache)

    check fileExists(tmp / "health" / "cache.json")

    let loaded = readHealthCache(tmp)
    check loaded.len == 2
    check loaded["abc123"].healthy == true
    check loaded["abc123"].test_exit_code == 0
    check loaded["abc123"].integration_test_exit_code == 0
    check loaded["abc123"].test_wall_seconds == 45
    check loaded["abc123"].integration_test_wall_seconds == 120
    check loaded["def456"].healthy == false
    check loaded["def456"].test_exit_code == 1

  test "readHealthCache parses JSON with correct field types":
    let tmp = getTempDir() / "scriptorium_test_health_cache_parse"
    createDir(tmp / "health")
    defer: removeDir(tmp)

    let jsonContent = """{"commit1": {"healthy": true, "timestamp": "2026-03-13T12:00:00Z", "test_exit_code": 0, "integration_test_exit_code": 0, "test_wall_seconds": 30, "integration_test_wall_seconds": 60}}"""
    writeFile(tmp / "health" / "cache.json", jsonContent)

    let cache = readHealthCache(tmp)
    check cache.len == 1
    check "commit1" in cache
    check cache["commit1"].healthy == true
    check cache["commit1"].timestamp == "2026-03-13T12:00:00Z"
    check cache["commit1"].test_wall_seconds == 30
    check cache["commit1"].integration_test_wall_seconds == 60

  test "writeHealthCache overwrites existing cache":
    let tmp = getTempDir() / "scriptorium_test_health_cache_overwrite"
    createDir(tmp)
    defer: removeDir(tmp)

    var cache1 = initTable[string, HealthCacheEntry]()
    cache1["abc"] = HealthCacheEntry(healthy: true, timestamp: "t1", test_exit_code: 0, integration_test_exit_code: 0, test_wall_seconds: 1, integration_test_wall_seconds: 2)
    writeHealthCache(tmp, cache1)

    var cache2 = initTable[string, HealthCacheEntry]()
    cache2["abc"] = HealthCacheEntry(healthy: true, timestamp: "t1", test_exit_code: 0, integration_test_exit_code: 0, test_wall_seconds: 1, integration_test_wall_seconds: 2)
    cache2["def"] = HealthCacheEntry(healthy: false, timestamp: "t2", test_exit_code: 1, integration_test_exit_code: 0, test_wall_seconds: 5, integration_test_wall_seconds: 0)
    writeHealthCache(tmp, cache2)

    let loaded = readHealthCache(tmp)
    check loaded.len == 2
    check "abc" in loaded
    check "def" in loaded

suite "per-ticket submit_pr state":
  test "consumeSubmitPrSummary with ticketId returns per-ticket summary":
    discard consumeSubmitPrSummary()
    setActiveTicketWorktree("/tmp/wt-a", "0001")
    setActiveTicketWorktree("/tmp/wt-b", "0002")
    defer:
      clearActiveTicketWorktree("0001")
      clearActiveTicketWorktree("0002")

    recordSubmitPrSummary("summary for 0001", "0001")
    recordSubmitPrSummary("summary for 0002", "0002")

    check consumeSubmitPrSummary("0001") == "summary for 0001"
    check consumeSubmitPrSummary("0002") == "summary for 0002"
    check consumeSubmitPrSummary("0001") == ""
    check consumeSubmitPrSummary("0002") == ""

  test "consumeSubmitPrSummary without ticketId returns first available":
    discard consumeSubmitPrSummary()
    recordSubmitPrSummary("some summary", "0005")
    let result = consumeSubmitPrSummary()
    check result == "some summary"
    check consumeSubmitPrSummary() == ""

  test "setActiveTicketWorktree registers multiple entries":
    clearActiveTicketWorktree()
    setActiveTicketWorktree("/tmp/wt-a", "0010")
    setActiveTicketWorktree("/tmp/wt-b", "0011")
    defer: clearActiveTicketWorktree()

    let a = getActiveTicketWorktree("0010")
    check a.worktreePath == "/tmp/wt-a"
    check a.ticketId == "0010"

    let b = getActiveTicketWorktree("0011")
    check b.worktreePath == "/tmp/wt-b"
    check b.ticketId == "0011"

  test "clearActiveTicketWorktree with ticketId removes only that entry":
    clearActiveTicketWorktree()
    setActiveTicketWorktree("/tmp/wt-a", "0020")
    setActiveTicketWorktree("/tmp/wt-b", "0021")
    defer: clearActiveTicketWorktree()

    clearActiveTicketWorktree("0020")
    let a = getActiveTicketWorktree("0020")
    check a.worktreePath == ""
    let b = getActiveTicketWorktree("0021")
    check b.worktreePath == "/tmp/wt-b"

  test "clearActiveTicketWorktree without ticketId removes all entries":
    setActiveTicketWorktree("/tmp/wt-a", "0030")
    setActiveTicketWorktree("/tmp/wt-b", "0031")
    clearActiveTicketWorktree()
    check getActiveTicketWorktree("0030").worktreePath == ""
    check getActiveTicketWorktree("0031").worktreePath == ""

suite "agent slot types":
  test "AgentSlot stores ticket metadata with role":
    let slot = AgentSlot(
      role: arCoder,
      ticketId: "0042",
      branch: "scriptorium/ticket-0042",
      worktree: "/tmp/worktrees/0042",
      startTime: 1234567890.0,
    )
    check slot.role == arCoder
    check slot.ticketId == "0042"
    check slot.branch == "scriptorium/ticket-0042"
    check slot.worktree == "/tmp/worktrees/0042"
    check slot.startTime == 1234567890.0

  test "AgentSlot manager uses areaId with empty branch and worktree":
    let slot = AgentSlot(
      role: arManager,
      areaId: "backend-api",
      startTime: 1234567890.0,
    )
    check slot.role == arManager
    check slot.areaId == "backend-api"
    check slot.branch == ""
    check slot.worktree == ""

  test "runningAgentCount returns zero initially":
    check runningAgentCount() == 0

  test "emptySlotCount returns maxAgents when no agents running":
    check emptySlotCount(4) == 4

suite "non-blocking tick loop":
  test "serial mode executes one ticket per tick when maxAgents is 1":
    let tmp = getTempDir() / "scriptorium_test_serial_tick"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nSerial test.\n")
    addTicketToPlan(tmp, "open", "0001-serial.md", "# Ticket 1\n\n**Area:** a\n")

    var codingCalled = false
    let fakeRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      if request.ticketId == "architect-areas":
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.startsWith("manager"):
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId == "0001-prediction":
        return AgentRunResult(exitCode: 1, attemptCount: 1, stdout: "")
      elif request.ticketId == "0001":
        codingCalled = true
        recordSubmitPrSummary("serial done", "0001")
        return AgentRunResult(exitCode: 0, attemptCount: 1, lastMessage: "Done.", timeoutKind: "none")
      else:
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "", timeoutKind: "none")

    var cfg = defaultConfig()
    cfg.concurrency.maxAgents = 1
    writeScriptoriumConfig(tmp, cfg)

    runOrchestratorForTicks(tmp, 1, fakeRunner)

    check codingCalled
    let files = planTreeFiles(tmp)
    # Serial mode: ticket submitted and merged in the same tick.
    check "tickets/done/0001-serial.md" in files
    check "tickets/open/0001-serial.md" notin files

suite "concurrent agent execution":
  test "two agents run concurrently in separate worktrees without interfering":
    let tmp = getTempDir() / "scriptorium_test_concurrent_agents"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    writeSpecInPlan(tmp, "# Spec\n\nConcurrent test.\n")
    addTicketToPlan(tmp, "open", "0001-alpha.md", "# Ticket Alpha\n\n**Area:** area-a\n")
    addTicketToPlan(tmp, "open", "0002-beta.md", "# Ticket Beta\n\n**Area:** area-b\n")

    var cfg = defaultConfig()
    cfg.concurrency.maxAgents = 2
    writeScriptoriumConfig(tmp, cfg)

    var codingCallCount = 0
    var codingCallLock: Lock
    initLock(codingCallLock)
    var seenTickets: seq[string] = @[]

    let fakeRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      if request.ticketId == "architect-areas":
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.startsWith("manager"):
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "")
      elif request.ticketId.endsWith("-prediction"):
        return AgentRunResult(exitCode: 1, attemptCount: 1, stdout: "")
      elif request.ticketId == "0001" or request.ticketId == "0002":
        {.cast(gcsafe).}:
          acquire(codingCallLock)
          inc codingCallCount
          seenTickets.add(request.ticketId)
          release(codingCallLock)
        recordSubmitPrSummary("done " & request.ticketId, request.ticketId)
        return AgentRunResult(exitCode: 0, attemptCount: 1, lastMessage: "Done.", timeoutKind: "none")
      else:
        return AgentRunResult(exitCode: 0, attemptCount: 1, stdout: "", timeoutKind: "none")

    runOrchestratorForTicks(tmp, 3, fakeRunner)

    acquire(codingCallLock)
    let finalCount = codingCallCount
    let finalTickets = seenTickets
    release(codingCallLock)
    deinitLock(codingCallLock)

    check finalCount == 2
    check "0001" in finalTickets
    check "0002" in finalTickets

    let files = planTreeFiles(tmp)
    check "tickets/open/0001-alpha.md" notin files
    check "tickets/open/0002-beta.md" notin files

  test "submit_pr correctly identifies calling agent ticket in parallel mode":
    let tmp = getTempDir() / "scriptorium_test_concurrent_submit_pr"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** area-x\n")
    addTicketToPlan(tmp, "open", "0002-second.md", "# Ticket 2\n\n**Area:** area-y\n")

    let assignment1 = assignOldestOpenTicket(tmp)
    let assignment2 = assignOldestOpenTicket(tmp)
    check assignment1.inProgressTicket.len > 0
    check assignment2.inProgressTicket.len > 0

    setActiveTicketWorktree(assignment1.worktree, "0001")
    setActiveTicketWorktree(assignment2.worktree, "0002")
    defer: clearActiveTicketWorktree()

    let httpServer = createOrchestratorServer()
    let submitPrHandler = httpServer.server.toolHandlers["submit_pr"]

    discard submitPrHandler(%*{"summary": "done ticket 1", "ticket_id": "0001"})
    discard submitPrHandler(%*{"summary": "done ticket 2", "ticket_id": "0002"})

    let summary1 = consumeSubmitPrSummary("0001")
    let summary2 = consumeSubmitPrSummary("0002")
    check summary1 == "done ticket 1"
    check summary2 == "done ticket 2"

  test "stall detection works independently per agent":
    let tmp = getTempDir() / "scriptorium_test_concurrent_stall"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addPassingMakefile(tmp)
    addTicketToPlan(tmp, "open", "0001-staller.md", "# Ticket Staller\n\n**Area:** area-s\n")
    addTicketToPlan(tmp, "open", "0002-submitter.md", "# Ticket Submitter\n\n**Area:** area-t\n")
    var stallCfg = defaultConfig()
    stallCfg.timeouts.codingAgentMaxAttempts = 2
    writeScriptoriumConfig(tmp, stallCfg)

    let assignment1 = assignOldestOpenTicket(tmp)
    let assignment2 = assignOldestOpenTicket(tmp)
    check assignment1.inProgressTicket.len > 0
    check assignment2.inProgressTicket.len > 0

    ticketStartTimes["0001"] = epochTime()
    ticketStartTimes["0002"] = epochTime()
    ticketAttemptCounts["0001"] = 0
    ticketAttemptCounts["0002"] = 0
    ticketCodingWalls["0001"] = 0.0
    ticketCodingWalls["0002"] = 0.0
    ticketTestWalls["0001"] = 0.0
    ticketTestWalls["0002"] = 0.0
    ticketModels["0001"] = ""
    ticketModels["0002"] = ""
    ticketStdoutBytes["0001"] = 0
    ticketStdoutBytes["0002"] = 0

    var stallCallCount = 0
    proc stallingRunner(request: AgentRunRequest): AgentRunResult =
      ## Stalls on every call: exit 0 without calling submit_pr.
      inc stallCallCount
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        lastMessage: "I stalled.",
        timeoutKind: "none",
      )

    proc submittingRunner(request: AgentRunRequest): AgentRunResult =
      ## Submits immediately on first call.
      recordSubmitPrSummary("submitted", "0002")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        lastMessage: "Done.",
        timeoutKind: "none",
      )

    let result1 = executeAssignedTicket(tmp, assignment1, stallingRunner)
    let result2 = executeAssignedTicket(tmp, assignment2, submittingRunner)

    check stallCallCount == 2
    check result1.submitted == false
    check result2.submitted == true

    let files = planTreeFiles(tmp)
    check "tickets/open/0001-staller.md" in files
    let hasMergeEntry = files.anyIt(it.startsWith("queue/merge/pending/") and it.contains("0002"))
    check hasMergeEntry

suite "token budget tracking":
  setup:
    ticketStdoutBytes.clear()

  test "getSessionStdoutBytes sums all ticket values":
    ticketStdoutBytes["0001"] = 1000
    ticketStdoutBytes["0002"] = 2000
    ticketStdoutBytes["0003"] = 3000
    check getSessionStdoutBytes() == 6000

  test "getSessionStdoutBytes returns 0 when empty":
    check getSessionStdoutBytes() == 0

  test "isTokenBudgetExceeded returns false when tokenBudgetMB is 0":
    ticketStdoutBytes["0001"] = 100 * 1024 * 1024
    check isTokenBudgetExceeded(0) == false

  test "isTokenBudgetExceeded returns false when tokenBudgetMB is negative":
    ticketStdoutBytes["0001"] = 100 * 1024 * 1024
    check isTokenBudgetExceeded(-1) == false

  test "isTokenBudgetExceeded returns true when budget exceeded":
    ticketStdoutBytes["0001"] = 5 * 1024 * 1024
    ticketStdoutBytes["0002"] = 6 * 1024 * 1024
    check isTokenBudgetExceeded(10) == true

  test "isTokenBudgetExceeded returns false when under budget":
    ticketStdoutBytes["0001"] = 2 * 1024 * 1024
    ticketStdoutBytes["0002"] = 3 * 1024 * 1024
    check isTokenBudgetExceeded(10) == false

  test "running agents not interrupted when budget exceeded":
    ## Verify that ticketStdoutBytes entries remain intact when budget is exceeded.
    ticketStdoutBytes["0001"] = 5 * 1024 * 1024
    ticketStdoutBytes["0002"] = 6 * 1024 * 1024
    let exceeded = isTokenBudgetExceeded(10)
    check exceeded == true
    # Existing entries are not cleared or modified.
    check ticketStdoutBytes["0001"] == 5 * 1024 * 1024
    check ticketStdoutBytes["0002"] == 6 * 1024 * 1024

suite "rate limit detection and backpressure":
  setup:
    resetRateLimitState()

  test "isRateLimited detects HTTP 429 rate limit":
    check isRateLimited("Error: HTTP 429 Too Many Requests") == true
    check isRateLimited("rate limit exceeded") == true
    check isRateLimited("rate_limit_error: quota exceeded") == true
    check isRateLimited("ratelimit hit, please retry") == true
    check isRateLimited("Error 429: rate limited") == true

  test "isRateLimited returns false for normal output":
    check isRateLimited("") == false
    check isRateLimited("Successfully completed task") == false
    check isRateLimited("Exit code 0") == false
    check isRateLimited("429 lines of code written") == false

  test "backoff timing increases exponentially":
    resetRateLimitState()
    recordRateLimit("0001")
    let backoff1 = rateLimitBackoffSeconds()
    check backoff1 == 2.0

    recordRateLimit("0002")
    let backoff2 = rateLimitBackoffSeconds()
    check backoff2 == 4.0

    recordRateLimit("0003")
    let backoff3 = rateLimitBackoffSeconds()
    check backoff3 == 8.0

    recordRateLimit("0004")
    let backoff4 = rateLimitBackoffSeconds()
    check backoff4 == 16.0

  test "backoff is capped at maximum":
    resetRateLimitState()
    for i in 1..20:
      recordRateLimit("0001")
    let backoff = rateLimitBackoffSeconds()
    check backoff == 120.0

  test "effective concurrency reduced on rate limit":
    resetRateLimitState()
    check effectiveMaxAgents(4) == 4

    recordRateLimit("0001")
    check effectiveMaxAgents(4) == 3

    recordRateLimit("0002")
    check effectiveMaxAgents(4) == 2

  test "effective concurrency never drops below 1":
    resetRateLimitState()
    for i in 1..10:
      recordRateLimit("0001")
    check effectiveMaxAgents(4) == 1

  test "concurrency restored after backoff expires":
    resetRateLimitState()
    recordRateLimit("0001")
    check effectiveMaxAgents(4) == 3
    check isRateLimitBackoffActive() == true

    # Simulate backoff expiry by setting backoff time in the past.
    rateLimitBackoffUntil = epochTime() - 1.0
    check isRateLimitBackoffActive() == false
    check effectiveMaxAgents(4) == 4
    check rateLimitConsecutiveCount == 0
    check rateLimitConcurrencyReduction == 0

  test "resetRateLimitState clears all state":
    recordRateLimit("0001")
    recordRateLimit("0002")
    check rateLimitConsecutiveCount == 2
    check rateLimitConcurrencyReduction > 0
    check rateLimitBackoffUntil > 0.0

    resetRateLimitState()
    check rateLimitConsecutiveCount == 0
    check rateLimitConcurrencyReduction == 0
    check rateLimitBackoffUntil == 0.0

  test "running agents not interrupted by backpressure":
    resetRateLimitState()
    recordRateLimit("0001")
    check isRateLimitBackoffActive() == true
    # Backpressure only affects new agent starts via effectiveMaxAgents.
    # Running agents tracked in runningAgentSlots are never modified.
    check runningAgentCount() == 0

suite "buildReviewAgentPrompt":
  test "contains expected sections":
    ## Verify the rendered prompt includes ticket, diff, area, and summary sections.
    let prompt = buildReviewAgentPrompt(
      "Fix the login bug",
      "--- a/login.nim\n+++ b/login.nim\n@@ -1 +1 @@\n-old\n+new",
      "area: auth\nResponsible for authentication flows.",
      "Fixed the login validation logic.",
    )
    check "Fix the login bug" in prompt
    check "old" in prompt
    check "new" in prompt
    check "area: auth" in prompt
    check "Fixed the login validation logic" in prompt

  test "contains review instructions and submit_review tool":
    ## Verify the prompt includes review instructions and the submit_review MCP tool.
    let prompt = buildReviewAgentPrompt("ticket", "diff", "area", "summary")
    check "submit_review" in prompt
    check "approve" in prompt
    check "request_changes" in prompt

  test "sections are delimited with markdown headers":
    ## Verify each section is labeled with a markdown header for parseability.
    let prompt = buildReviewAgentPrompt("ticket", "diff", "area", "summary")
    check "## Ticket Content" in prompt
    check "## Changes" in prompt
    check "## Area Context" in prompt
    check "## Coding Agent Summary" in prompt
    check "## Instructions" in prompt

  test "empty diff does not crash":
    ## Verify the prompt builder handles an empty diff gracefully.
    let prompt = buildReviewAgentPrompt("ticket", "", "area", "summary")
    check "## Changes" in prompt
    check "## Ticket Content" in prompt

  test "whitespace-only diff handled gracefully":
    ## Verify the prompt builder handles a whitespace-only diff.
    let prompt = buildReviewAgentPrompt("ticket", "   \n  \n", "area", "summary")
    check "## Changes" in prompt

suite "review feedback truncation":
  setup:
    discard consumeReviewDecision()

  test "feedback under limit passes through unchanged":
    ## Verify feedback well under ReviewFeedbackMaxBytes is stored verbatim.
    let feedback = 'a'.repeat(100)
    recordReviewDecision("approve", feedback)
    let decision = consumeReviewDecision()
    check decision.feedback == feedback
    check decision.feedback.len == 100

  test "feedback exactly at limit passes through unchanged":
    ## Verify feedback exactly at ReviewFeedbackMaxBytes is stored verbatim.
    let feedback = 'b'.repeat(ReviewFeedbackMaxBytes)
    recordReviewDecision("approve", feedback)
    let decision = consumeReviewDecision()
    check decision.feedback == feedback
    check decision.feedback.len == ReviewFeedbackMaxBytes

  test "feedback one byte over limit is truncated with marker":
    ## Verify feedback at 4097 bytes is truncated with the truncation marker.
    let feedback = 'c'.repeat(ReviewFeedbackMaxBytes + 1)
    recordReviewDecision("approve", feedback)
    let decision = consumeReviewDecision()
    check decision.feedback.len == ReviewFeedbackMaxBytes
    check decision.feedback.endsWith(ReviewTruncationMarker)
    let expectedText = 'c'.repeat(ReviewFeedbackMaxBytes - ReviewTruncationMarker.len)
    check decision.feedback == expectedText & ReviewTruncationMarker

  test "large feedback is truncated with marker":
    ## Verify feedback at 2x the limit is truncated to ReviewFeedbackMaxBytes with marker.
    let feedback = 'd'.repeat(ReviewFeedbackMaxBytes * 2)
    recordReviewDecision("request_changes", feedback)
    let decision = consumeReviewDecision()
    check decision.feedback.len == ReviewFeedbackMaxBytes
    check decision.feedback.endsWith(ReviewTruncationMarker)

suite "progress-based stall detection":
  test "progress timeout triggers stall continuation flow":
    ## When the agent returns with timeoutKind="progress", it should be treated
    ## as a stall and retried with a continuation prompt.
    let tmp = getTempDir() / "scriptorium_test_progress_stall"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0080-progress.md", "# Ticket 80\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 950)

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "Makefile", "test:\n\t@echo OK\nintegration-test:\n\t@echo OK\n")

    var callCount = 0
    var capturedRequests: seq[AgentRunRequest]
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      inc callCount
      capturedRequests.add(request)
      if callCount == 2:
        callSubmitPrTool("progress stall fixed")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: if callCount == 1: 137 else: 0,
        attempt: callCount,
        attemptCount: 1,
        stdout: "reasoning output...",
        lastMessage: "stuck in a loop",
        timeoutKind: if callCount == 1: "progress" else: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunner)

    check callCount == 2
    check capturedRequests.len == 2
    let retryPrompt = capturedRequests[1].prompt
    check "Ticket 80" in retryPrompt

  test "progress timeout reopens ticket after maxAttempts exhausted":
    ## When the agent repeatedly hits progress timeout and exhausts all attempts,
    ## the ticket should be reopened with timeout_progress failure reason.
    let tmp = getTempDir() / "scriptorium_test_progress_exhaust"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0081-progress-exhaust.md", "# Ticket 81\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 951)

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "Makefile", "test:\n\t@echo OK\nintegration-test:\n\t@echo OK\n")
    let before = planCommitCount(tmp)

    var callCount = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      inc callCount
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 137,
        attempt: callCount,
        attemptCount: 1,
        stdout: "reasoning output...",
        lastMessage: "still stuck",
        timeoutKind: "progress",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunner)

    let after = planCommitCount(tmp)
    check after > before
    let files = planTreeFiles(tmp)
    check "tickets/open/0081-progress-exhaust.md" in files
    check "tickets/in-progress/0081-progress-exhaust.md" notin files

  test "progressTimeoutMs is passed through to agent request":
    ## Verify that the config value for codingAgentProgressTimeoutMs is
    ## passed through to the AgentRunRequest.
    let tmp = getTempDir() / "scriptorium_test_progress_config"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0082-progress-cfg.md", "# Ticket 82\n\n**Area:** a\n")
    writeOrchestratorEndpointConfig(tmp, 952)

    let assignment = assignOldestOpenTicket(tmp)
    writeFile(assignment.worktree / "Makefile", "test:\n\t@echo OK\nintegration-test:\n\t@echo OK\n")

    var capturedRequest: AgentRunRequest
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      capturedRequest = request
      callSubmitPrTool("progress config check done")
      result = AgentRunResult(
        backend: harnessCodex,
        command: @["codex", "exec"],
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        stdout: "",
        lastMessage: "done",
        timeoutKind: "none",
      )

    discard executeAssignedTicket(tmp, assignment, fakeRunner)

    check capturedRequest.progressTimeoutMs == 600_000

suite "resolveDefaultBranch":
  test "detects master when it exists":
    let tmp = getTempDir() / "scriptorium_test_resolve_master"
    if dirExists(tmp):
      removeDir(tmp)
    createDir(tmp)
    defer:
      removeDir(tmp)
    discard execCmdEx("git -C " & tmp & " init")
    discard execCmdEx("git -C " & tmp & " config user.email test@test.com")
    discard execCmdEx("git -C " & tmp & " config user.name Test")
    discard execCmdEx("git -C " & tmp & " commit --allow-empty -m initial")
    check resolveDefaultBranch(tmp) == "master"

  test "detects main when master does not exist":
    let tmp = getTempDir() / "scriptorium_test_resolve_main"
    if dirExists(tmp):
      removeDir(tmp)
    createDir(tmp)
    defer:
      removeDir(tmp)
    discard execCmdEx("git -C " & tmp & " init -b main")
    discard execCmdEx("git -C " & tmp & " config user.email test@test.com")
    discard execCmdEx("git -C " & tmp & " config user.name Test")
    discard execCmdEx("git -C " & tmp & " commit --allow-empty -m initial")
    check resolveDefaultBranch(tmp) == "main"

  test "errors when no known default branch exists":
    let tmp = getTempDir() / "scriptorium_test_resolve_none"
    if dirExists(tmp):
      removeDir(tmp)
    createDir(tmp)
    defer:
      removeDir(tmp)
    discard execCmdEx("git -C " & tmp & " init -b feature")
    discard execCmdEx("git -C " & tmp & " config user.email test@test.com")
    discard execCmdEx("git -C " & tmp & " config user.name Test")
    discard execCmdEx("git -C " & tmp & " commit --allow-empty -m initial")
    expect IOError:
      discard resolveDefaultBranch(tmp)

  test "prefers origin/HEAD when set":
    let tmp = getTempDir() / "scriptorium_test_resolve_origin_head"
    if dirExists(tmp):
      removeDir(tmp)
    createDir(tmp)
    defer:
      removeDir(tmp)
    discard execCmdEx("git -C " & tmp & " init -b main")
    discard execCmdEx("git -C " & tmp & " config user.email test@test.com")
    discard execCmdEx("git -C " & tmp & " config user.name Test")
    discard execCmdEx("git -C " & tmp & " commit --allow-empty -m initial")
    # Create a fake remote and set origin/HEAD.
    discard execCmdEx("git -C " & tmp & " remote add origin " & tmp)
    discard execCmdEx("git -C " & tmp & " fetch origin")
    discard execCmdEx("git -C " & tmp & " remote set-head origin main")
    check resolveDefaultBranch(tmp) == "main"
