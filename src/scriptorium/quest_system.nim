import
  std/[algorithm, os, strformat, strutils, times],
  jsony,
  ./[agent_pool, agent_runner, architect_agent, config, git_ops, lock_management, logging,
     loop_system, prompt_builders, shared_state, ticket_metadata]

const
  QuestVerdictsDir* = "quests/verdicts"
  QuestWriteAllowPrefixes = ["spec.md", "areas", "tickets/open", "quests", "docs"]
  QuestScopeName = "architect quest"
  QuestTicketId = "quest"
  QuestSlugMaxLen = 40
  RecentVerdictCount = 3

type
  QuestVerdict* = object
    done*: bool
    reason*: string
    iteration*: int

proc ensureQuestsDir*(planPath: string) =
  ## Create the quests directories if they do not exist.
  let questsPath = planPath / PlanQuestsDir
  if not dirExists(questsPath):
    createDir(questsPath)
  let verdictsPath = planPath / QuestVerdictsDir
  if not dirExists(verdictsPath):
    createDir(verdictsPath)
  let donePath = planPath / PlanQuestsDoneDir
  if not dirExists(donePath):
    createDir(donePath)

proc isQuestActive*(planPath: string): bool =
  ## Return true when an active quest file exists on the plan branch.
  fileExists(planPath / PlanQuestActivePath)

proc readActiveQuest*(planPath: string): string =
  ## Read the active quest prompt from the plan branch.
  let path = planPath / PlanQuestActivePath
  if not fileExists(path):
    raise newException(ValueError, "no active quest found at " & PlanQuestActivePath)
  result = readFile(path)

proc writeQuestActiveFile*(planPath: string, questPrompt: string) =
  ## Write the active quest prompt to the plan branch.
  ensureQuestsDir(planPath)
  atomicWriteFile(planPath / PlanQuestActivePath, questPrompt)

proc parseQuestVerdict*(jsonContent: string): QuestVerdict =
  ## Parse the architect-written verdict file content. Raises on malformed JSON.
  let trimmed = jsonContent.strip()
  if trimmed.len == 0:
    raise newException(ValueError, "quest verdict is empty")
  result = fromJson(trimmed, QuestVerdict)

proc listVerdictFiles*(planPath: string): seq[string] =
  ## Return sorted list of verdict file paths.
  let dirPath = planPath / QuestVerdictsDir
  if not dirExists(dirPath):
    return @[]
  for f in walkFiles(dirPath / "*.json"):
    result.add(f)
  result.sort()

proc nextVerdictNumber*(planPath: string): int =
  ## Return the next verdict iteration number based on existing verdict files.
  let files = listVerdictFiles(planPath)
  if files.len == 0:
    return 1
  let lastFile = extractFilename(files[^1])
  let base = lastFile.split('.')[0]
  var numStr = ""
  for ch in base:
    if ch in {'0'..'9'}:
      numStr.add(ch)
  if numStr.len == 0:
    return 1
  result = parseInt(numStr) + 1

proc readRecentVerdicts*(planPath: string, count: int = RecentVerdictCount): string =
  ## Read the most recent N verdict files formatted for the architect prompt.
  let files = listVerdictFiles(planPath)
  if files.len == 0:
    return "No prior verdicts."
  let start = max(0, files.len - count)
  var parts: seq[string]
  for i in start..<files.len:
    let name = extractFilename(files[i])
    let content = readFile(files[i]).strip()
    parts.add(&"### {name}\n\n{content}")
  result = parts.join("\n\n")

proc buildTicketSummary*(planPath: string): string =
  ## Build a short ticket count summary string for the architect prompt.
  let
    openCount = listMarkdownFiles(planPath / PlanTicketsOpenDir).len
    inProgressCount = listMarkdownFiles(planPath / PlanTicketsInProgressDir).len
    doneCount = listMarkdownFiles(planPath / PlanTicketsDoneDir).len
    stuckCount = listMarkdownFiles(planPath / PlanTicketsStuckDir).len
  result = &"- open: {openCount}\n- in-progress: {inProgressCount}\n- done: {doneCount}\n- stuck: {stuckCount}"

proc slugifyPrompt*(prompt: string): string =
  ## Convert a quest prompt to a filesystem-safe slug for archive filenames.
  var buf = newStringOfCap(QuestSlugMaxLen)
  var lastDash = false
  for ch in prompt.strip().toLowerAscii():
    if buf.len >= QuestSlugMaxLen:
      break
    if ch in {'a'..'z', '0'..'9'}:
      buf.add(ch)
      lastDash = false
    elif not lastDash and buf.len > 0:
      buf.add('-')
      lastDash = true
  while buf.len > 0 and buf[^1] == '-':
    buf.setLen(buf.len - 1)
  if buf.len == 0:
    buf = "quest"
  result = buf

proc verdictFilePath(planPath: string, iteration: int): string =
  ## Return the path for a per-iteration verdict file.
  planPath / QuestVerdictsDir / &"{iteration:03d}.json"

proc archiveVerdictForIteration(planPath: string, verdict: QuestVerdict, iteration: int) =
  ## Copy the verdict into the verdicts history directory.
  ensureQuestsDir(planPath)
  let target = verdictFilePath(planPath, iteration)
  atomicWriteFile(target, verdict.toJson() & "\n")

proc commitQuestProgress(planPath: string, iteration: int) =
  ## Stage and commit any quest, spec, areas, tickets, or docs changes for this iteration.
  for relPath in QuestWriteAllowPrefixes:
    let absPath = planPath / relPath
    if fileExists(absPath) or dirExists(absPath):
      gitRun(planPath, "add", relPath)
  if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
    gitRun(planPath, "commit", "-m", &"scriptorium: quest iteration {iteration}")

proc archiveQuest*(repoPath: string, finalVerdict: QuestVerdict) =
  ## Move the active quest and verdict into the quests/done archive as one commit.
  discard withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
    let activePath = planPath / PlanQuestActivePath
    if not fileExists(activePath):
      logWarn("quest: no active quest to archive")
      return false
    ensureQuestsDir(planPath)
    let prompt = readFile(activePath)
    let timestamp = now().utc.format("yyyyMMdd-HHmmss")
    let slug = slugifyPrompt(prompt)
    let archiveRel = PlanQuestsDoneDir & "/" & timestamp & "-" & slug & ".md"
    let archivePath = planPath / archiveRel
    let doneText = if finalVerdict.done: "done" else: "interrupted"
    let body = &"""# Quest archive

**Status:** {doneText}
**Final iteration:** {finalVerdict.iteration}
**Reason:** {finalVerdict.reason}

## Original Prompt

{prompt}
"""
    atomicWriteFile(archivePath, body)
    removeFile(activePath)
    let verdictPath = planPath / PlanQuestVerdictPath
    if fileExists(verdictPath):
      removeFile(verdictPath)
    gitRun(planPath, "add", PlanQuestsDir)
    if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
      gitRun(planPath, "commit", "-m", &"scriptorium: archive quest ({doneText})")
    true
  )

proc startQuest*(repoPath: string, questPrompt: string) =
  ## Write the active quest file to the plan branch and commit it.
  if questPrompt.strip().len == 0:
    raise newException(ValueError, "quest prompt cannot be empty")
  discard withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
    if isQuestActive(planPath):
      raise newException(ValueError,
        "an active quest already exists at quests/active.md — clear it before starting a new quest")
    writeQuestActiveFile(planPath, questPrompt)
    gitRun(planPath, "add", PlanQuestActivePath)
    if gitCheck(planPath, "diff", "--cached", "--quiet") != 0:
      gitRun(planPath, "commit", "-m", "scriptorium: start quest")
    true
  )

proc runQuestEvalIfDrained*(repoPath: string, runner: AgentRunner): bool =
  ## Run one architect quest evaluation when queues are drained and no agents are running.
  ## Returns true when the architect declared the quest done (and shouldRun has been flipped).
  if runner.isNil:
    raise newException(ValueError, "agent runner is required")
  if runningAgentCount() != 0:
    return false

  let drained = withPlanWorktree(repoPath, proc(planPath: string): bool =
    isQueueDrained(planPath) and isQuestActive(planPath)
  )
  if not drained:
    return false

  let cfg = loadConfig(repoPath)
  result = withLockedPlanWorktree(repoPath, proc(planPath: string): bool =
    ensureQuestsDir(planPath)
    let questPrompt = readActiveQuest(planPath)
    let iterNum = nextVerdictNumber(planPath)
    let recentVerdicts = readRecentVerdicts(planPath)
    let ticketSummary = buildTicketSummary(planPath)
    let prompt = buildArchitectQuestPrompt(
      repoPath, planPath, questPrompt, iterNum, recentVerdicts, ticketSummary,
    )
    logInfo(&"quest: iteration {iterNum}, invoking architect")
    let t0 = epochTime()
    discard runPlanArchitectRequest(
      runner,
      repoPath,
      planPath,
      cfg.agents.architect,
      prompt,
      QuestTicketId,
    )
    let architectElapsed = epochTime() - t0
    logInfo(&"quest: architect completed ({architectElapsed:.1f}s)")

    enforceWritePrefixAllowlist(planPath, QuestWriteAllowPrefixes, QuestScopeName)

    let verdictPath = planPath / PlanQuestVerdictPath
    if not fileExists(verdictPath):
      logWarn("quest: architect did not write quests/active-verdict.json — continuing")
      commitQuestProgress(planPath, iterNum)
      return false

    let raw = readFile(verdictPath)
    let verdict = parseQuestVerdict(raw)
    archiveVerdictForIteration(planPath, verdict, iterNum)
    commitQuestProgress(planPath, iterNum)

    if verdict.done:
      logInfo(&"quest: architect declared done at iteration {iterNum} — {verdict.reason}")
      shouldRun = false
      return true
    else:
      logInfo(&"quest: iteration {iterNum} not done — {verdict.reason}")
      return false
  )

proc latestQuestVerdict*(repoPath: string): QuestVerdict =
  ## Return the most recent verdict from the plan branch, or a zero-value if none exist.
  result = withPlanWorktree(repoPath, proc(planPath: string): QuestVerdict =
    let files = listVerdictFiles(planPath)
    if files.len == 0:
      return QuestVerdict()
    result = parseQuestVerdict(readFile(files[^1]))
  )
