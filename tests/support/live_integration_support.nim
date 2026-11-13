## Shared helpers for live end-to-end integration tests.

import
  std/[algorithm, os, osproc, posix, sequtils, strutils, tempfiles, times],
  jsony,
  scriptorium/[config, git_ops, lock_management]

const
  LiveIntegrationRoot* = "/tmp/scriptorium/integration"
  CliBinaryName = "scriptorium_integration_live"
  DefaultIntegrationModel* = ""
  DefaultIntegrationCodingModel* = ""
  CodexAuthPathEnv* = "CODEX_AUTH_FILE"
  LiveOrchestratorBasePort* = 23000
  LiveOrchestratorPortRange = 800
  PollIntervalMs* = 500
  PositiveTimeoutMs* = 900_000
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

const AcpBackend {.strdefine.} = "codex"

proc integrationModel*(): string =
  ## Use the adapter default unless a caller explicitly configures a model.
  ""

proc integrationCodingModel*(): string =
  ## Keep live tests independent of retired model identifiers.
  ""

proc integrationHarness*(): Harness =
  ## Select a real backend through the named Make target's compile definition.
  case AcpBackend
  of "codex": harnessCodex
  of "claude": harnessClaudeCode
  of "grok": harnessGrokBuild
  else: raise newException(ValueError, "Unknown ACP backend: " & AcpBackend)

proc integrationCodingHarness*(): Harness =
  ## Exercise the same selected backend for every workflow role.
  integrationHarness()

proc requiredAgentBinary*(): string =
  ## Require the actual ACP executable rather than a legacy exec-mode CLI.
  case integrationHarness()
  of harnessCodex: "codex-acp"
  of harnessClaudeCode: "claude-agent-acp"
  of harnessGrokBuild: "grok"
  else: raise newException(ValueError, "Retired backend")

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
  of harnessTypoi, harnessHermes:
    raise newException(ValueError, "Retired backend")
  of harnessGrokBuild:
    let hasApiKey = getEnv("XAI_API_KEY", "").len > 0
    let hasOauth = fileExists(expandTilde("~/.grok/auth.json"))
    result = hasApiKey or hasOauth

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
  ## Open scriptorium/plan via the persistent per-caller plan worktree.
  discard suffix
  discard withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
    action(planPath)
    result = true
  )

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
  let gitignoreContent =
    "# ignore files with no extension:\n" &
    "*\n" &
    "!*/\n" &
    "!*.*\n" &
    "!Makefile\n\n" &
    "# normal ignores:\n" &
    "nimcache*\n" &
    ".*\n" &
    "!.gitignore\n"
  writeFile(repoPath / "Makefile", makefileContent)
  writeFile(repoPath / ".gitignore", gitignoreContent)
  runCmdOrDie("git -C " & quoteShell(repoPath) & " add Makefile .gitignore")
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
  let agent = AgentConfig(acpAgent: profileName(h), harness: h, model: model,
    hardTimeout: 300_000, noOutputTimeout: 120_000, progressTimeout: 180_000)
  cfg.agents.architect = agent
  cfg.agents.manager = agent
  cfg.agents.reviewer = agent
  cfg.agents.audit = agent
  cfg.agents.coding = AgentConfig(acpAgent: profileName(cHarness), harness: cHarness,
    model: cModel, hardTimeout: 300_000, noOutputTimeout: 120_000, progressTimeout: 180_000)
  cfg.concurrency.maxAgents = 2
  cfg.diskSpaceMinGB = 0
  cfg.remoteSync.enabled = false
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
    cliBinaryPath = ProjectRoot / ".build" / "test-binaries" / (CliBinaryName & "-" & AcpBackend & "-" & $getCurrentProcessId())
    runCmdOrDie(
      "nim c --hints:off --nimcache:" & quoteShell(ProjectRoot / ".build" / "test-cache" / ("live-cli-" & AcpBackend & "-" & $getCurrentProcessId())) & " -o:" & quoteShell(cliBinaryPath) & " " & quoteShell(ProjectRoot / "src/scriptorium.nim")
    )
  result = cliBinaryPath

proc orchestratorPort*(offset: int): int =
  ## Return a deterministic local orchestrator port for one test offset.
  result = LiveOrchestratorBasePort + (getCurrentProcessId().int mod LiveOrchestratorPortRange) + offset

proc latestOrchestratorLogPath*(repoPath: string): string =
  ## Return the latest orchestrator log file path for one test repository.
  let logDir = repoPath / ".scriptorium" / "logs" / "orchestrator"
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
  ## Require clean shutdown and report timeout/crash cleanup as a test failure.
  var code = process.peekExitCode()
  if code == -1:
    discard posix.kill(Pid(processID(process)), SIGINT)
    code = process.waitForExit(ShutdownTimeoutMs)
  if code == -1:
    process.kill()
    discard process.waitForExit()
  process.close()
  doAssert code == 0, "Orchestrator did not stop cleanly; exit=" & $code

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
