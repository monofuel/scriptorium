import
  std/[algorithm, os, strformat, strutils, times],
  ./[agent_runner, architect_agent, config, git_ops, lock_management, logging, prompt_builders, shared_state, ticket_metadata]

const
  IterationsDir* = "docs" / "iterations"
  LegacyIterationLogPath* = "iteration_log.md"

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

proc ensureIterationsDir*(planPath: string) =
  ## Create the iterations directory if it does not exist.
  let dirPath = planPath / IterationsDir
  if not dirExists(dirPath):
    createDir(dirPath)

proc iterationFilePath*(planPath: string, iteration: int): string =
  ## Return the path for an iteration file.
  planPath / IterationsDir / &"{iteration:03d}.md"

proc listIterationFiles*(planPath: string): seq[string] =
  ## Return sorted list of iteration file paths.
  let dirPath = planPath / IterationsDir
  if not dirExists(dirPath):
    return @[]
  var files: seq[string]
  for f in walkFiles(dirPath / "*.md"):
    files.add(f)
  files.sort()
  result = files

proc readRecentIterations*(planPath: string, count: int = 2): string =
  ## Read the most recent N iteration files, concatenated.
  let files = listIterationFiles(planPath)
  if files.len == 0:
    return ""
  let start = max(0, files.len - count)
  var parts: seq[string]
  for i in start..<files.len:
    parts.add(readFile(files[i]))
  result = parts.join("\n\n")

proc nextIterationNumber*(planPath: string): int =
  ## Return the next iteration number based on existing iteration files.
  let files = listIterationFiles(planPath)
  if files.len == 0:
    # Check legacy iteration_log.md for migration.
    let legacyPath = planPath / LegacyIterationLogPath
    if fileExists(legacyPath):
      let content = readFile(legacyPath)
      var highest = 0
      for line in content.splitLines():
        if line.startsWith("## Iteration "):
          let rest = line[len("## Iteration ")..^1].strip()
          var numStr = ""
          for ch in rest:
            if ch in {'0'..'9'}:
              numStr.add(ch)
            else:
              break
          if numStr.len > 0:
            let num = parseInt(numStr)
            if num > highest:
              highest = num
      if highest > 0:
        return highest + 1
    return 1
  # Parse number from the last filename (e.g. "045.md" -> 45).
  let lastFile = extractFilename(files[^1])
  let base = lastFile.split('.')[0]
  var numStr = ""
  for ch in base:
    if ch in {'0'..'9'}:
      numStr.add(ch)
  if numStr.len == 0:
    return 1
  result = parseInt(numStr) + 1

proc writeIterationEntry*(planPath: string, iteration: int, feedbackOutput: string, assessment: string, strategy: string, tradeoffs: string) =
  ## Write a formatted iteration entry to its own file.
  ensureIterationsDir(planPath)
  let filePath = iterationFilePath(planPath, iteration)
  let entry = &"""## Iteration {iteration}

**Feedback Output:**

{feedbackOutput}

**Assessment:**

{assessment}

**Strategy:**

{strategy}

**Tradeoffs:**

{tradeoffs}
"""
  writeFile(filePath, entry)

proc commitIterationEntry*(planPath: string, iteration: int) =
  ## Stage and commit the iteration entry file.
  let relPath = IterationsDir / &"{iteration:03d}.md"
  let fullPath = planPath / relPath
  if not fileExists(fullPath):
    return
  gitRun(planPath, "add", relPath)
  if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
    gitRun(planPath, "commit", "-m", &"chore: add iteration {iteration} entry")

const
  LoopWriteAllowPrefixes = ["spec.md", "areas", "tickets/open", "docs"]
  LoopScopeName = "architect loop"
  LoopTicketId = "loop"
  MaxLoopRetries* = 2
  LoopRetryPromptSuffix = "\n\n## IMPORTANT — Retry\n\nYour previous attempt did not modify spec.md. The loop REQUIRES spec changes to drive work. You MUST update spec.md with concrete changes based on the feedback. Do not just write an assessment — change the spec."

proc specWasModified(planPath: string): bool =
  ## Check whether spec.md has uncommitted changes or is untracked.
  let specPath = planPath / PlanSpecPath
  if not fileExists(specPath):
    return false
  let changed = gitCheck(planPath, "diff", "--quiet", PlanSpecPath) != 0
  let untracked = gitCheck(planPath, "ls-files", "--error-unmatch", PlanSpecPath) != 0
  result = changed or untracked

proc runArchitectLoopIteration*(repoPath: string, caller: string, runner: AgentRunner, feedbackOutput: string): bool =
  ## Run one architect loop iteration: build prompt, invoke architect, commit results.
  ## Returns true when spec.md was modified, false when the architect failed to produce changes.
  let cfg = loadConfig(repoPath)
  let goal = cfg.loop.goal
  if goal.len == 0:
    logWarn("loop goal is empty, skipping architect loop iteration")
    return false

  result = withLockedPlanWorktree(repoPath, caller, proc(planPath: string): bool =
    ensureIterationsDir(planPath)
    let recentIters = readRecentIterations(planPath)
    let iterNum = nextIterationNumber(planPath)
    var prompt = buildArchitectLoopPrompt(repoPath, planPath, goal, recentIters, feedbackOutput, iterNum)
    logInfo(&"loop: iteration {iterNum}, invoking architect")

    var specModified = false
    for attempt in 1..MaxLoopRetries:
      if attempt > 1:
        prompt = prompt & LoopRetryPromptSuffix
        logInfo(&"loop: retrying architect (attempt {attempt}/{MaxLoopRetries}), spec was not modified")

      let t0 = epochTime()
      discard runPlanArchitectRequest(
        runner,
        repoPath,
        planPath,
        cfg.agents.architect,
        prompt,
        LoopTicketId,
      )
      let architectElapsed = epochTime() - t0

      enforceWritePrefixAllowlist(planPath, LoopWriteAllowPrefixes, LoopScopeName)

      let modified = specWasModified(planPath)
      logInfo(&"loop: architect completed (attempt {attempt}/{MaxLoopRetries}, {architectElapsed:.1f}s), spec modified: {modified}")

      if modified:
        specModified = true
        break

    # If the architect did not write its own iteration entry, write a fallback.
    let expectedPath = iterationFilePath(planPath, iterNum)
    if not fileExists(expectedPath):
      let assessment = if specModified: "Architect did not write an iteration entry."
                       else: "Architect did not modify spec.md after " & $MaxLoopRetries & " attempts."
      writeIterationEntry(planPath, iterNum, feedbackOutput,
        assessment, "Architect did not write a strategy.", "None noted.")

    commitIterationEntry(planPath, iterNum)

    if not specModified:
      logWarn(&"loop: architect did not modify spec.md after {MaxLoopRetries} attempts")
      return false

    logInfo("loop: committing spec changes")
    gitRun(planPath, "add", PlanSpecPath)
    if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
      gitRun(planPath, "commit", "-m", "scriptorium: update spec from architect loop")

    true
  )
