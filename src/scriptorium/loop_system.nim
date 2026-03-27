import
  std/[os, strformat, strutils],
  ./[agent_runner, architect_agent, config, git_ops, lock_management, logging, prompt_builders, shared_state, ticket_metadata]

const
  IterationLogPath* = "iteration_log.md"

proc isQueueDrained*(planPath: string): bool =
  ## Check whether all ticket and merge queues are empty.
  let
    openFiles = listMarkdownFiles(planPath / PlanTicketsOpenDir)
    inProgressFiles = listMarkdownFiles(planPath / PlanTicketsInProgressDir)
    pendingFiles = listMarkdownFiles(planPath / PlanMergeQueuePendingDir)
  result = openFiles.len == 0 and inProgressFiles.len == 0 and pendingFiles.len == 0

type
  FeedbackResult* = object
    output*: string
    exitCode*: int
    timedOut*: bool

proc runFeedbackCommand*(repoPath: string, command: string, timeoutMs: int = DefaultFeedbackTimeoutMs): FeedbackResult =
  ## Run a shell command synchronously in the given repo directory and return its output.
  ## Never raises on failure or timeout — the caller gets full context to pass to the architect.
  try:
    let commandResult = runCommandCapture(repoPath, "sh", @["-c", command], timeoutMs)
    result = FeedbackResult(output: commandResult.output, exitCode: commandResult.exitCode, timedOut: false)
  except IOError as e:
    result = FeedbackResult(output: e.msg, exitCode: -1, timedOut: true)

proc formatFeedbackResult*(fb: FeedbackResult): string =
  ## Format a FeedbackResult into a string suitable for the architect prompt.
  if fb.timedOut:
    result = &"[TIMEOUT] Feedback command timed out.\n{fb.output}"
  elif fb.exitCode != 0:
    let exitCode = fb.exitCode
    result = &"[EXIT CODE {exitCode}] Feedback command failed.\n{fb.output}"
  else:
    result = fb.output

proc readIterationLog*(planPath: string): string =
  ## Read the iteration log file content, returning empty string if missing.
  let filePath = planPath / IterationLogPath
  if fileExists(filePath):
    result = readFile(filePath)
  else:
    result = ""

proc nextIterationNumber*(planPath: string): int =
  ## Parse the log to find the highest Iteration N heading and return N+1.
  let content = readIterationLog(planPath)
  if content.len == 0:
    return 1
  var highest = 0
  for line in content.splitLines():
    if line.startsWith("## Iteration "):
      let numStr = line[len("## Iteration ")..^1].strip()
      let num = parseInt(numStr)
      if num > highest:
        highest = num
  result = highest + 1

proc appendIterationLogEntry*(planPath: string, iteration: int, feedbackOutput: string, assessment: string, strategy: string, tradeoffs: string) =
  ## Append a formatted iteration entry to the log file.
  let filePath = planPath / IterationLogPath
  var entry = &"""
## Iteration {iteration}

**Feedback Output:**

{feedbackOutput}

**Assessment:**

{assessment}

**Strategy:**

{strategy}

**Tradeoffs:**

{tradeoffs}

"""
  let existing = readIterationLog(planPath)
  if existing.len > 0 and not existing.endsWith("\n"):
    entry = "\n" & entry
  let f = open(filePath, fmAppend)
  f.write(entry)
  f.close()

proc commitIterationLog*(planPath: string) =
  ## Stage and commit iteration_log.md if it has changed.
  let rc = gitCheck(planPath, "diff", "--quiet", IterationLogPath)
  let untracked = gitCheck(planPath, "ls-files", "--error-unmatch", IterationLogPath)
  if rc == 0 and untracked == 0:
    return
  gitRun(planPath, "add", IterationLogPath)
  gitRun(planPath, "commit", "-m", "chore: update iteration log")

const
  LoopWriteAllowPrefixes = ["spec.md", "areas", "tickets/open", "iteration_log.md"]
  LoopScopeName = "architect loop"
  LoopTicketId = "loop"

proc runArchitectLoopIteration*(repoPath: string, runner: AgentRunner, feedbackOutput: string): bool =
  ## Run one architect loop iteration: build prompt, invoke architect, commit results.
  let cfg = loadConfig(repoPath)
  let goal = cfg.loop.goal
  if goal.len == 0:
    logWarn("loop goal is empty, skipping architect loop iteration")
    return false

  result = withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
    let iterLog = readIterationLog(planPath)
    let iterNum = nextIterationNumber(planPath)
    let prompt = buildArchitectLoopPrompt(repoPath, planPath, goal, iterLog, feedbackOutput, iterNum)

    discard runPlanArchitectRequest(
      runner,
      repoPath,
      planPath,
      cfg.agents.architect,
      prompt,
      LoopTicketId,
    )

    enforceWritePrefixAllowlist(planPath, LoopWriteAllowPrefixes, LoopScopeName)

    let nextNum = nextIterationNumber(planPath)
    if nextNum == iterNum:
      appendIterationLogEntry(planPath, iterNum, feedbackOutput,
        "Architect did not write an assessment.", "Architect did not write a strategy.", "None noted.")

    commitIterationLog(planPath)

    let specPath = planPath / PlanSpecPath
    if fileExists(specPath):
      let specChanged = gitCheck(planPath, "diff", "--quiet", PlanSpecPath) != 0
      let specUntracked = gitCheck(planPath, "ls-files", "--error-unmatch", PlanSpecPath) != 0
      if specChanged or specUntracked:
        gitRun(planPath, "add", PlanSpecPath)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          gitRun(planPath, "commit", "-m", "scriptorium: update spec from architect loop")
        writeSpecHashMarker(planPath)
        gitRun(planPath, "add", SpecHashMarkerPath)
        if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
          gitRun(planPath, "commit", "-m", "scriptorium: update spec hash marker")

    true
  )
