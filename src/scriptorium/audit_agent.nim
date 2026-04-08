import
  std/[os, strformat, strutils, times],
  jsony,
  ./[agent_runner, architect_agent, config, git_ops, lock_management, logging,
     prompt_builders, shared_state]

const
  AuditLogDirName* = "audit"
  AuditStatePath* = "audit_state.json"
  AuditCallerName* = "plan-audit"
  DefaultAuditHardTimeoutMs* = 300_000
  DefaultAuditNoOutputTimeoutMs* = 120_000

type
  AuditState* = object
    lastAuditedCommit*: string

proc loadAuditState*(planPath: string): AuditState =
  ## Load the audit state from the plan worktree.
  let statePath = planPath / AuditStatePath
  if not fileExists(statePath):
    return AuditState()
  let raw = readFile(statePath)
  result = fromJson(raw, AuditState)

proc saveAuditState*(planPath: string, state: AuditState) =
  ## Write the audit state file in the plan worktree.
  writeFile(planPath / AuditStatePath, state.toJson())

proc computeAuditDiff*(repoPath: string, lastAuditedCommit: string): string =
  ## Compute the cumulative diff from the last audited commit to the default branch HEAD.
  let defaultBranch = resolveDefaultBranch(repoPath)
  let diffRange = lastAuditedCommit & ".." & defaultBranch
  let (exitCode, output) = runCommandCapture(repoPath, "git", @["diff", diffRange])
  if exitCode != 0:
    raise newException(IOError, &"git diff {diffRange} failed: {output.strip()}")
  result = output

proc writeAuditReport*(repoPath: string, report: string): string =
  ## Write the audit report to the logs directory and return the path.
  let logDir = planAgentLogRoot(repoPath, AuditLogDirName)
  createDir(logDir)
  let timestamp = now().utc.format("yyyy-MM-dd'T'HH-mm-ss'Z'")
  let reportPath = logDir / (timestamp & ".md")
  writeFile(reportPath, report)
  result = reportPath

proc runAuditAgent*(repoPath: string, runner: AgentRunner = nil): string =
  ## Run the audit agent and return the report path. Returns empty string if no changes.
  let cfg = loadConfig(repoPath)

  var spec: string
  var agentsMd: string
  var lastAuditedCommit: string

  discard withPlanWorktree(repoPath, AuditCallerName, proc(planPath: string): bool =
    spec = loadSpecFromPlanPath(planPath)
    let agentsPath = planPath / "AGENTS.md"
    if fileExists(agentsPath):
      agentsMd = readFile(agentsPath)
    else:
      let repoAgentsPath = repoPath / "AGENTS.md"
      if fileExists(repoAgentsPath):
        agentsMd = readFile(repoAgentsPath)
    let state = loadAuditState(planPath)
    lastAuditedCommit = state.lastAuditedCommit
    true
  )

  if lastAuditedCommit.len == 0:
    let defaultBranch = resolveDefaultBranch(repoPath)
    let (exitCode, output) = runCommandCapture(repoPath, "git",
      @["rev-list", "--max-parents=0", defaultBranch])
    if exitCode != 0:
      raise newException(IOError, &"git rev-list failed: {output.strip()}")
    lastAuditedCommit = output.strip().splitLines()[0]

  let diff = computeAuditDiff(repoPath, lastAuditedCommit)
  if diff.strip().len == 0:
    logInfo("audit: no changes since last audit, skipping")
    return ""

  let prompt = buildAuditAgentPrompt(spec, agentsMd, lastAuditedCommit, diff)

  let auditCfg = cfg.agents.audit
  let hardTimeoutMs =
    if auditCfg.hardTimeout > 0: auditCfg.hardTimeout
    else: DefaultAuditHardTimeoutMs
  let noOutputTimeoutMs =
    if auditCfg.noOutputTimeout > 0: auditCfg.noOutputTimeout
    else: DefaultAuditNoOutputTimeoutMs
  let request = AgentRunRequest(
    prompt: prompt,
    workingDir: repoPath,
    harness: auditCfg.harness,
    model: resolveModel(auditCfg.model),
    reasoningEffort: auditCfg.reasoningEffort,
    mcpEndpoint: cfg.endpoints.local,
    ticketId: "audit",
    skipGitRepoCheck: true,
    logRoot: planAgentLogRoot(repoPath, AuditLogDirName),
    hardTimeoutMs: hardTimeoutMs,
    noOutputTimeoutMs: noOutputTimeoutMs,
  )

  let agentResult =
    if runner.isNil: runAgent(request)
    else: runner(request)

  if agentResult.exitCode != 0:
    logWarn(&"audit agent exited with code {agentResult.exitCode}")

  let report = consumeAuditReport()
  if report.len == 0:
    logWarn("audit: agent did not submit a report via submit_audit_report")
    return ""

  let reportPath = writeAuditReport(repoPath, report)
  logInfo(&"audit: report written to {reportPath}")

  let headCommit = defaultBranchHeadCommit(repoPath)
  discard withLockedPlanWorktree(repoPath, AuditCallerName, proc(planPath: string): bool =
    let newState = AuditState(lastAuditedCommit: headCommit)
    saveAuditState(planPath, newState)
    gitRun(planPath, "add", AuditStatePath)
    gitRun(planPath, "commit", "-m", "scriptorium: update audit state")
    true
  )
  logInfo(&"audit: state updated to commit {headCommit}")
  result = reportPath
