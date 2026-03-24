## Shared helpers for live end-to-end integration tests.

import
  std/[algorithm, os, osproc, posix, sequtils, strutils, tempfiles, times],
  jsony,
  scriptorium/config

const
  LiveIntegrationRoot* = "/tmp/scriptorium/integration"
  CliBinaryName = "scriptorium_integration_live"
  DefaultIntegrationModel* = "gpt-5.4"
  CodexAuthPathEnv* = "CODEX_AUTH_FILE"
  LiveOrchestratorBasePort* = 23000
  PollIntervalMs* = 500
  PositiveTimeoutMs* = 300_000
  NegativeTimeoutMs* = 120_000
  ShutdownTimeoutMs = 15_000
  LogTailChars = 16_000
  EulerExpectedAnswer* = "233168"
  EulerDebugBinary = "./multiples-test-bin"
  EulerReleaseBinary = "./multiples-release-bin"

let
  ProjectRoot = getCurrentDir()
var
  cliBinaryPath = ""

proc integrationModel*(): string =
  ## Return the configured integration model from env, or the default.
  result = getEnv("SCRIPTORIUM_TEST_MODEL", "")
  if result.len == 0:
    result = getEnv("CODEX_INTEGRATION_MODEL", DefaultIntegrationModel)

proc integrationCodingModel*(): string =
  ## Return the coding-role model override, falling back to integrationModel.
  result = getEnv("SCRIPTORIUM_TEST_CODING_MODEL", "")
  if result.len == 0:
    result = integrationModel()

proc integrationHarness*(): Harness =
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

proc integrationCodingHarness*(): Harness =
  ## Return the coding-role harness override, falling back to integrationHarness.
  let envVal = getEnv("SCRIPTORIUM_TEST_CODING_HARNESS", "").strip().toLowerAscii()
  if envVal.len > 0:
    case envVal
    of "codex": result = harnessCodex
    of "claude-code": result = harnessClaudeCode
    of "typoi": result = harnessTypoi
    else:
      raise newException(ValueError, "unknown SCRIPTORIUM_TEST_CODING_HARNESS: " & envVal)
  else:
    result = integrationHarness()

proc requiredAgentBinary*(): string =
  ## Return the binary name needed for the configured test harness.
  let h = integrationHarness()
  case h
  of harnessCodex: result = "codex"
  of harnessClaudeCode: result = "claude"
  of harnessTypoi: result = "typoi"

proc codexAuthPath*(): string =
  ## Return the configured Codex auth file path used for OAuth credentials.
  let overridePath = getEnv(CodexAuthPathEnv, "").strip()
  if overridePath.len > 0:
    result = overridePath
  else:
    result = expandTilde("~/.codex/auth.json")

proc hasAgentAuth*(): bool =
  ## Return true when API keys are available for the configured test harness.
  let h = integrationHarness()
  case h
  of harnessCodex:
    let hasApiKey = getEnv("OPENAI_API_KEY", "").len > 0 or getEnv("CODEX_API_KEY", "").len > 0
    result = hasApiKey or fileExists(codexAuthPath())
  of harnessClaudeCode:
    let hasApiKey = getEnv("ANTHROPIC_API_KEY", "").len > 0
    let hasOauth = fileExists(expandTilde("~/.claude/.credentials.json"))
    result = hasApiKey or hasOauth
  of harnessTypoi:
    result = true

proc runCmdOrDie*(cmd: string) =
  ## Run one shell command and fail immediately when it exits non-zero.
  let (output, rc) = execCmdEx(cmd)
  doAssert rc == 0, cmd & "\n" & output

proc makeTestRepo(path: string) =
  ## Create a minimal git repository at path suitable for integration tests.
  if dirExists(path):
    removeDir(path)
  createDir(path)
  runCmdOrDie("git -C " & quoteShell(path) & " init")
  runCmdOrDie("git -C " & quoteShell(path) & " config user.email test@test.com")
  runCmdOrDie("git -C " & quoteShell(path) & " config user.name Test")
  runCmdOrDie("git -C " & quoteShell(path) & " commit --allow-empty -m initial")

proc withTempLiveRepo*(prefix: string, action: proc(repoPath: string)) =
  ## Create one temporary live integration repository and clean it up afterwards.
  createDir("/tmp/scriptorium")
  createDir(LiveIntegrationRoot)
  let repoPath = createTempDir(prefix, "", LiveIntegrationRoot)
  defer:
    removeDir(repoPath)
  makeTestRepo(repoPath)
  action(repoPath)

proc withPlanWorktree*(repoPath: string, suffix: string, action: proc(planPath: string)) =
  ## Open scriptorium/plan in a temporary worktree for direct fixture mutations.
  let planPath = createTempDir("scriptorium_integration_live_" & suffix & "_", "", getTempDir())
  removeDir(planPath)
  defer:
    if dirExists(planPath):
      removeDir(planPath)

  runCmdOrDie("git -C " & quoteShell(repoPath) & " worktree add " & quoteShell(planPath) & " scriptorium/plan")
  defer:
    discard execCmdEx("git -C " & quoteShell(repoPath) & " worktree remove --force " & quoteShell(planPath))

  action(planPath)

proc writeSpecInPlan*(repoPath: string, content: string, commitMessage: string) =
  ## Replace spec.md on the plan branch and commit fixture content.
  withPlanWorktree(repoPath, "write_spec", proc(planPath: string) =
    writeFile(planPath / "spec.md", content)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add spec.md")
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m " & quoteShell(commitMessage))
  )

proc addAreaToPlan*(repoPath: string, fileName: string, content: string, commitMessage: string) =
  ## Add one area markdown file to the plan branch and commit it.
  withPlanWorktree(repoPath, "add_area", proc(planPath: string) =
    let relPath = "areas/" & fileName
    writeFile(planPath / relPath, content)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add " & quoteShell(relPath))
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m " & quoteShell(commitMessage))
  )

proc addTicketToPlan*(repoPath: string, fileName: string, content: string, commitMessage: string) =
  ## Add one open ticket markdown file to the plan branch and commit it.
  withPlanWorktree(repoPath, "add_ticket", proc(planPath: string) =
    let relPath = "tickets/open/" & fileName
    writeFile(planPath / relPath, content)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add " & quoteShell(relPath))
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m " & quoteShell(commitMessage))
  )

proc addPassingMakefile*(repoPath: string) =
  ## Add passing quality-gate targets for live orchestrator tests.
  writeFile(
    repoPath / "Makefile",
    "test:\n\t@echo PASS test\n\nintegration-test:\n\t@echo PASS integration-test\n",
  )
  runCmdOrDie("git -C " & quoteShell(repoPath) & " add Makefile")
  runCmdOrDie("git -C " & quoteShell(repoPath) & " commit -m integration-live-add-passing-makefile")

proc addEulerMakefile*(repoPath: string) =
  ## Add Euler-specific quality gates that validate multiples.nim only after it exists.
  let makefileContent =
    "EXPECTED=" & EulerExpectedAnswer & "\n\n" &
    "test:\n" &
    "\t@test ! -f multiples.nim || { rm -f " & EulerDebugBinary & " && nim c --nimcache:.nimcache-test -o:" & EulerDebugBinary & " multiples.nim >/dev/null && output=$$(" & EulerDebugBinary & "); test \"$$output\" = \"$(EXPECTED)\"; }\n\n" &
    "integration-test:\n" &
    "\t@test ! -f multiples.nim || { rm -f " & EulerReleaseBinary & " && nim c --nimcache:.nimcache-release -d:release -o:" & EulerReleaseBinary & " multiples.nim >/dev/null && output=$$(" & EulerReleaseBinary & "); test \"$$output\" = \"$(EXPECTED)\"; }\n"
  writeFile(repoPath / "Makefile", makefileContent)
  runCmdOrDie("git -C " & quoteShell(repoPath) & " add Makefile")
  runCmdOrDie("git -C " & quoteShell(repoPath) & " commit -m integration-live-add-euler-makefile")

proc writeScriptoriumConfig*(repoPath: string, cfg: Config) =
  ## Write one typed scriptorium.json payload for integration configuration.
  writeFile(repoPath / "scriptorium.json", cfg.toJson())

proc writeLiveConfig*(repoPath: string, endpoint: string, codingModel: string = "") =
  ## Write a live-test config that points all roles at the supplied endpoint.
  var cfg = defaultConfig()
  let model = integrationModel()
  let h = integrationHarness()
  let cModel = if codingModel.len > 0: codingModel else: integrationCodingModel()
  let cHarness = if codingModel.len > 0: inferHarness(codingModel) else: integrationCodingHarness()
  cfg.agents.architect = AgentConfig(harness: h, model: model)
  cfg.agents.manager = AgentConfig(harness: h, model: model)
  cfg.agents.coding = AgentConfig(harness: cHarness, model: cModel)
  cfg.endpoints.local = endpoint
  writeScriptoriumConfig(repoPath, cfg)

proc planTreeFiles*(repoPath: string): seq[string] =
  ## Return tracked file paths from the plan branch tree.
  let (output, rc) = execCmdEx("git -C " & quoteShell(repoPath) & " ls-tree -r --name-only scriptorium/plan")
  doAssert rc == 0
  result = output.splitLines().filterIt(it.len > 0)

proc pendingQueueFiles*(repoPath: string): seq[string] =
  ## Return pending merge-queue markdown entries sorted by file name.
  let files = planTreeFiles(repoPath)
  result = files.filterIt(it.startsWith("queue/merge/pending/") and it.endsWith(".md"))
  result.sort()

proc readPlanFile*(repoPath: string, relPath: string): string =
  ## Read one file from the plan branch tree.
  let (output, rc) = execCmdEx(
    "git -C " & quoteShell(repoPath) & " show scriptorium/plan:" & relPath
  )
  doAssert rc == 0, relPath
  result = output

proc ensureCliBinary*(): string =
  ## Build and cache the scriptorium CLI binary for live daemon tests.
  if cliBinaryPath.len == 0:
    cliBinaryPath = getTempDir() / CliBinaryName
    runCmdOrDie(
      "nim c -o:" & quoteShell(cliBinaryPath) & " " & quoteShell(ProjectRoot / "src/scriptorium.nim")
    )
  result = cliBinaryPath

proc orchestratorPort*(offset: int): int =
  ## Return a deterministic local orchestrator port for one test offset.
  result = LiveOrchestratorBasePort + (getCurrentProcessId().int mod 1000) + offset

proc latestOrchestratorLogPath*(repoPath: string): string =
  ## Return the latest orchestrator log file path for one test repository.
  let logDir = "/tmp/scriptorium" / lastPathPart(repoPath)
  if dirExists(logDir):
    for filePath in walkDirRec(logDir):
      if filePath.toLowerAscii().endsWith(".log"):
        result.add(filePath & "\n")

  if result.len > 0:
    let paths = result.splitLines().filterIt(it.len > 0).sorted()
    result = paths[^1]
  else:
    result = ""

proc truncateTail(value: string, maxChars: int): string =
  ## Return at most maxChars from the end of value.
  if maxChars < 1:
    result = ""
  elif value.len <= maxChars:
    result = value
  else:
    result = value[(value.len - maxChars)..^1]

proc orchestratorLogTail*(repoPath: string): string =
  ## Return a short tail preview from the latest orchestrator log.
  let logPath = latestOrchestratorLogPath(repoPath)
  if logPath.len > 0 and fileExists(logPath):
    result = truncateTail(readFile(logPath), LogTailChars)
  else:
    result = "<no orchestrator log found>"

proc e2eDebugContext*(repoPath: string): string =
  ## Return a compact debug context block for live E2E failures.
  let
    latestLogPath = latestOrchestratorLogPath(repoPath)
    planFiles = planTreeFiles(repoPath).join("\n")
    logTail = orchestratorLogTail(repoPath)
  result =
    "Fixture repo: " & repoPath & "\n" &
    "Latest orchestrator log: " & latestLogPath & "\n\n" &
    "Plan files:\n" & planFiles & "\n\n" &
    "Log tail:\n" & logTail

proc waitForCondition*(timeoutMs: int, pollMs: int, condition: proc(): bool): bool =
  ## Poll condition until true or timeout.
  let startedAt = epochTime()
  var elapsedMs = 0.0
  while elapsedMs < timeoutMs.float:
    if condition():
      result = true
      break
    sleep(pollMs)
    elapsedMs = (epochTime() - startedAt) * 1000.0

proc stopProcessWithSigint*(process: Process) =
  ## Send SIGINT to one process, wait briefly, then close process handles.
  if process.peekExitCode() == -1:
    let pid = processID(process)
    discard posix.kill(Pid(pid), SIGINT)
    discard process.waitForExit(ShutdownTimeoutMs)
  process.close()

proc startOrchestrator*(repoPath: string): Process =
  ## Start the live orchestrator process in repoPath.
  result = startProcess(
    ensureCliBinary(),
    workingDir = repoPath,
    args = @["run"],
    options = {poUsePath, poParentStreams},
  )

proc initLiveRepo*(repoPath: string) =
  ## Initialize one repository via the scriptorium init CLI subcommand.
  let bin = ensureCliBinary()
  let cmd = quoteShell(bin) & " init " & quoteShell(repoPath)
  runCmdOrDie(cmd)
