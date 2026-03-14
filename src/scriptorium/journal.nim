## Write-ahead journal infrastructure for atomic plan branch transitions.

import
  std/[json, os, sha1, strformat, times],
  ./[git_ops, logging]

const
  JournalFileName* = ".scriptorium-journal.json"

type
  JournalStepAction* = enum
    jsWrite = "write"
    jsMove = "move"
    jsRemove = "remove"

  JournalStep* = object
    action*: JournalStepAction
    path*: string
    content*: string
    contentHash*: string
    source*: string
    destination*: string

  Journal* = object
    operation*: string
    timestamp*: string
    steps*: seq[JournalStep]
    commitMessage*: string

proc journalPath*(worktreeRoot: string): string =
  ## Return the full path to the journal file in a worktree.
  result = worktreeRoot / JournalFileName

proc journalExists*(worktreeRoot: string): bool =
  ## Return true when a journal file exists in the worktree root.
  result = fileExists(journalPath(worktreeRoot))

proc computeHash(content: string): string =
  ## Compute SHA-1 hex digest for content verification.
  result = $secureHash(content)

proc stepToJson(step: JournalStep): JsonNode =
  ## Serialize a journal step to JSON.
  result = %*{"action": $step.action}
  case step.action
  of jsWrite:
    result["path"] = %step.path
    result["content"] = %step.content
    result["contentHash"] = %step.contentHash
  of jsMove:
    result["source"] = %step.source
    result["destination"] = %step.destination
  of jsRemove:
    result["path"] = %step.path

proc stepFromJson(node: JsonNode): JournalStep =
  ## Deserialize a journal step from JSON.
  let actionStr = node["action"].getStr()
  case actionStr
  of "write":
    result = JournalStep(
      action: jsWrite,
      path: node["path"].getStr(),
      content: node["content"].getStr(),
      contentHash: node["contentHash"].getStr(),
    )
  of "move":
    result = JournalStep(
      action: jsMove,
      source: node["source"].getStr(),
      destination: node["destination"].getStr(),
    )
  of "remove":
    result = JournalStep(action: jsRemove, path: node["path"].getStr())
  else:
    raise newException(ValueError, &"unknown journal step action: {actionStr}")

proc journalToJson*(j: Journal): JsonNode =
  ## Serialize a journal to JSON.
  var stepsArr = newJArray()
  for step in j.steps:
    stepsArr.add(stepToJson(step))
  result = %*{
    "operation": j.operation,
    "timestamp": j.timestamp,
    "steps": stepsArr,
    "commit_message": j.commitMessage,
  }

proc journalFromJson(node: JsonNode): Journal =
  ## Deserialize a journal from JSON.
  result.operation = node["operation"].getStr()
  result.timestamp = node["timestamp"].getStr()
  result.commitMessage = node["commit_message"].getStr()
  for stepNode in node["steps"]:
    result.steps.add(stepFromJson(stepNode))

proc readJournal*(worktreeRoot: string): Journal =
  ## Read and parse the journal file from the worktree root.
  let content = readFile(journalPath(worktreeRoot))
  let node = parseJson(content)
  result = journalFromJson(node)

proc writeStep*(step: JournalStep): JournalStep =
  ## Create a write step with auto-computed content hash.
  result = JournalStep(
    action: jsWrite,
    path: step.path,
    content: step.content,
    contentHash: computeHash(step.content),
  )

proc newWriteStep*(path: string, content: string): JournalStep =
  ## Create a write step for a file path and content.
  result = JournalStep(
    action: jsWrite,
    path: path,
    content: content,
    contentHash: computeHash(content),
  )

proc newMoveStep*(source: string, destination: string): JournalStep =
  ## Create a move step for a source and destination path.
  result = JournalStep(action: jsMove, source: source, destination: destination)

proc newRemoveStep*(path: string): JournalStep =
  ## Create a remove step for a file path.
  result = JournalStep(action: jsRemove, path: path)

proc beginJournalTransition*(
    worktreeRoot: string,
    operation: string,
    steps: seq[JournalStep],
    commitMessage: string,
) =
  ## Write the journal file and commit it to begin a transition.
  let journal = Journal(
    operation: operation,
    timestamp: now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    steps: steps,
    commitMessage: commitMessage,
  )
  let jsonContent = pretty(journalToJson(journal))
  writeFile(journalPath(worktreeRoot), jsonContent)
  gitRun(worktreeRoot, "add", JournalFileName)
  let beginMsg = &"scriptorium: begin transition — {operation}"
  gitRun(worktreeRoot, "commit", "-m", beginMsg)
  logInfo(&"journal: began transition — {operation}")

proc executeJournalSteps*(worktreeRoot: string) =
  ## Execute the filesystem operations described in the journal.
  let journal = readJournal(worktreeRoot)
  for step in journal.steps:
    case step.action
    of jsWrite:
      let fullPath = worktreeRoot / step.path
      createDir(parentDir(fullPath))
      writeFile(fullPath, step.content)
    of jsMove:
      let srcPath = worktreeRoot / step.source
      let dstPath = worktreeRoot / step.destination
      createDir(parentDir(dstPath))
      moveFile(srcPath, dstPath)
    of jsRemove:
      let fullPath = worktreeRoot / step.path
      if fileExists(fullPath):
        removeFile(fullPath)
  gitRun(worktreeRoot, "add", "-A")
  gitRun(worktreeRoot, "commit", "-m", journal.commitMessage)
  logInfo(&"journal: executed steps — {journal.operation}")

proc completeJournalTransition*(worktreeRoot: string) =
  ## Remove the journal file and commit to complete the transition.
  let jPath = journalPath(worktreeRoot)
  if fileExists(jPath):
    removeFile(jPath)
  gitRun(worktreeRoot, "add", "-A")
  gitRun(worktreeRoot, "commit", "-m", "scriptorium: complete transition")
  logInfo("journal: transition complete")

proc isStepApplied(worktreeRoot: string, step: JournalStep): bool =
  ## Check whether a single journal step has been applied.
  case step.action
  of jsWrite:
    let fullPath = worktreeRoot / step.path
    if not fileExists(fullPath):
      return false
    let currentHash = computeHash(readFile(fullPath))
    result = currentHash == step.contentHash
  of jsMove:
    let srcPath = worktreeRoot / step.source
    let dstPath = worktreeRoot / step.destination
    result = fileExists(dstPath) and not fileExists(srcPath)
  of jsRemove:
    let fullPath = worktreeRoot / step.path
    result = not fileExists(fullPath)

proc replayOrRollbackJournal*(worktreeRoot: string) =
  ## Recover from a crashed transition by replaying or rolling back.
  if not journalExists(worktreeRoot):
    return

  let journal = readJournal(worktreeRoot)
  var appliedCount = 0
  for step in journal.steps:
    if isStepApplied(worktreeRoot, step):
      inc appliedCount

  if appliedCount == journal.steps.len:
    gitRun(worktreeRoot, "add", "-A")
    gitRun(worktreeRoot, "commit", "-m", journal.commitMessage)
    removeFile(journalPath(worktreeRoot))
    gitRun(worktreeRoot, "add", "-A")
    gitRun(worktreeRoot, "commit", "-m", "scriptorium: complete transition")
    logInfo("recovery: completed interrupted transition")
  elif appliedCount == 0:
    gitRun(worktreeRoot, "checkout", "--", ".")
    let jPath = journalPath(worktreeRoot)
    if fileExists(jPath):
      removeFile(jPath)
    gitRun(worktreeRoot, "add", "-A")
    gitRun(worktreeRoot, "commit", "-m", "scriptorium: complete transition")
    logInfo("recovery: rolled back incomplete transition")
  else:
    for step in journal.steps:
      if not isStepApplied(worktreeRoot, step):
        case step.action
        of jsWrite:
          let fullPath = worktreeRoot / step.path
          createDir(parentDir(fullPath))
          writeFile(fullPath, step.content)
        of jsMove:
          let srcPath = worktreeRoot / step.source
          let dstPath = worktreeRoot / step.destination
          createDir(parentDir(dstPath))
          moveFile(srcPath, dstPath)
        of jsRemove:
          let fullPath = worktreeRoot / step.path
          if fileExists(fullPath):
            removeFile(fullPath)
    gitRun(worktreeRoot, "add", "-A")
    gitRun(worktreeRoot, "commit", "-m", journal.commitMessage)
    removeFile(journalPath(worktreeRoot))
    gitRun(worktreeRoot, "add", "-A")
    gitRun(worktreeRoot, "commit", "-m", "scriptorium: complete transition")
    logInfo("recovery: replayed partial transition")
