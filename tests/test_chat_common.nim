import
  std/[osproc, os, strutils, tempfiles],
  scriptorium/[chat_common, git_ops, lock_management, pause_flag]

const
  TestCaller = "test-chat-common"

proc makeTestRepo(path: string) =
  ## Create a minimal git repository at path with an initial commit.
  if dirExists(path):
    removeDir(path)
  createDir(path)
  discard execCmdEx("git -C " & path & " init")
  discard execCmdEx("git -C " & path & " config user.email test@test.com")
  discard execCmdEx("git -C " & path & " config user.name Test")
  writeFile(path / "README.md", "initial")
  discard execCmdEx("git -C " & path & " add README.md")
  discard execCmdEx("git -C " & path & " commit -m initial")

proc setupPlanBranch(repoPath: string, setupProc: proc(planDir: string)) =
  ## Create scriptorium/plan branch with directory structure from setupProc.
  discard execCmdEx("git -C " & repoPath & " checkout --orphan scriptorium/plan")
  discard execCmdEx("git -C " & repoPath & " rm -rf .")
  setupProc(repoPath)
  discard execCmdEx("git -C " & repoPath & " add -A")
  discard execCmdEx("git -C " & repoPath & " commit -m plan-setup --allow-empty")
  discard execCmdEx("git -C " & repoPath & " checkout master")

proc cleanupTestRepo(repoPath: string) =
  ## Tear down plan worktree and remove the temp repo.
  teardownPlanWorktree(repoPath, TestCaller)
  removeDir(repoPath)

proc testParseChatModeAsk() =
  ## Verify "ask:" prefix parses to chatModeAsk with explicit=true.
  let (mode, text, explicit) = parseChatMode("ask: what is this?")
  doAssert mode == chatModeAsk
  doAssert text == "what is this?"
  doAssert explicit == true
  echo "[OK] parseChatMode ask prefix"

proc testParseChatModePlan() =
  ## Verify "plan:" prefix parses to chatModePlan with explicit=true.
  let (mode, text, explicit) = parseChatMode("plan: build a feature")
  doAssert mode == chatModePlan
  doAssert text == "build a feature"
  doAssert explicit == true
  echo "[OK] parseChatMode plan prefix"

proc testParseChatModeDo() =
  ## Verify "do:" prefix parses to chatModeDo with explicit=true.
  let (mode, text, explicit) = parseChatMode("do: run the thing")
  doAssert mode == chatModeDo
  doAssert text == "run the thing"
  doAssert explicit == true
  echo "[OK] parseChatMode do prefix"

proc testParseChatModeDefault() =
  ## Verify no prefix defaults to chatModePlan with explicit=false.
  let (mode, text, explicit) = parseChatMode("just a message")
  doAssert mode == chatModePlan
  doAssert text == "just a message"
  doAssert explicit == false
  echo "[OK] parseChatMode default (no prefix)"

proc testParseChatModeCaseInsensitive() =
  ## Verify prefix matching is case insensitive.
  let (mode1, text1, explicit1) = parseChatMode("ASK: upper case")
  doAssert mode1 == chatModeAsk
  doAssert text1 == "upper case"
  doAssert explicit1 == true

  let (mode2, text2, explicit2) = parseChatMode("Do: mixed case")
  doAssert mode2 == chatModeDo
  doAssert text2 == "mixed case"
  doAssert explicit2 == true

  let (mode3, text3, explicit3) = parseChatMode("PLAN: all caps")
  doAssert mode3 == chatModePlan
  doAssert text3 == "all caps"
  doAssert explicit3 == true
  echo "[OK] parseChatMode case insensitive"

proc testParseChatModeWhitespace() =
  ## Verify leading and trailing whitespace is handled.
  let (mode, text, explicit) = parseChatMode("  ask:  hello world  ")
  doAssert mode == chatModeAsk
  doAssert text == "hello world"
  doAssert explicit == true
  echo "[OK] parseChatMode whitespace handling"

proc testChatModeEnumValues() =
  ## Verify all ChatMode enum values exist.
  doAssert chatModePlan != chatModeAsk
  doAssert chatModeChat != chatModeIgnore
  doAssert chatModeDo != chatModeChat
  echo "[OK] ChatMode enum values"

proc testTruncateMessageUnderLimit() =
  ## Verify messages under the limit are returned unchanged.
  let msg = "short message"
  let result = truncateMessage(msg, 2000)
  doAssert result == msg
  echo "[OK] truncateMessage under limit"

proc testTruncateMessageAtLimit() =
  ## Verify messages exactly at the limit are returned unchanged.
  let msg = 'x'.repeat(2000)
  let result = truncateMessage(msg, 2000)
  doAssert result == msg
  doAssert result.len == 2000
  echo "[OK] truncateMessage at limit"

proc testTruncateMessageOverLimit() =
  ## Verify messages over the limit are truncated with marker.
  let msg = 'x'.repeat(3000)
  let result = truncateMessage(msg, 2000)
  doAssert result.len == 2000
  doAssert result.endsWith(TruncatedMarker)
  echo "[OK] truncateMessage over limit"

proc testTruncateMessageCustomLimit() =
  ## Verify truncation works with a custom limit (e.g. Mattermost 16383).
  let msg = 'y'.repeat(20000)
  let result = truncateMessage(msg, 16383)
  doAssert result.len == 16383
  doAssert result.endsWith(TruncatedMarker)
  echo "[OK] truncateMessage custom limit"

proc testHandleHelp() =
  ## Verify handleHelp returns a message containing all commands.
  let result = handleHelp()
  doAssert "/status" in result
  doAssert "/queue" in result
  doAssert "/pause" in result
  doAssert "/resume" in result
  doAssert "/help" in result
  doAssert "/restart" in result
  doAssert "ask:" in result
  doAssert "plan:" in result
  doAssert "do:" in result
  echo "[OK] handleHelp contains all commands"

proc testHandlePauseNotPaused() =
  ## Verify handlePause writes the flag and returns confirmation.
  let tmp = createTempDir("chat_pause_", "", getTempDir())
  defer: removeDir(tmp)
  createDir(tmp / ManagedStateDirName)

  let result = handlePause(tmp)
  doAssert "paused" in result.toLowerAscii()
  doAssert isPaused(tmp)
  echo "[OK] handlePause when not paused"

proc testHandlePauseAlreadyPaused() =
  ## Verify handlePause returns already-paused message when flag exists.
  let tmp = createTempDir("chat_pause_already_", "", getTempDir())
  defer: removeDir(tmp)
  createDir(tmp / ManagedStateDirName)

  writePauseFlag(tmp)
  let result = handlePause(tmp)
  doAssert "already paused" in result.toLowerAscii()
  doAssert isPaused(tmp)
  echo "[OK] handlePause when already paused"

proc testHandleResumeWhenPaused() =
  ## Verify handleResume removes the flag and returns confirmation.
  let tmp = createTempDir("chat_resume_", "", getTempDir())
  defer: removeDir(tmp)
  createDir(tmp / ManagedStateDirName)

  writePauseFlag(tmp)
  let result = handleResume(tmp)
  doAssert "resumed" in result.toLowerAscii()
  doAssert not isPaused(tmp)
  echo "[OK] handleResume when paused"

proc testHandleResumeWhenNotPaused() =
  ## Verify handleResume returns not-paused message when no flag exists.
  let tmp = createTempDir("chat_resume_noop_", "", getTempDir())
  defer: removeDir(tmp)
  createDir(tmp / ManagedStateDirName)

  let result = handleResume(tmp)
  doAssert "was not paused" in result.toLowerAscii()
  doAssert not isPaused(tmp)
  echo "[OK] handleResume when not paused"

proc testTruncateMessageWithSpecNote() =
  ## Verify that response + spec note is properly truncated when combined length exceeds limit.
  let specNote = "\n[spec.md updated]"
  let longResponse = 'x'.repeat(1995) & specNote
  let result = truncateMessage(longResponse, 2000)
  doAssert result.len == 2000
  doAssert result.endsWith(TruncatedMarker)
  echo "[OK] truncateMessage with spec note over limit"

proc testTruncateMessageWithSpecNoteUnderLimit() =
  ## Verify that response + spec note is preserved when combined length is under limit.
  let specNote = "\n[spec.md updated]"
  let shortResponse = "Spec updated." & specNote
  let result = truncateMessage(shortResponse, 2000)
  doAssert result == shortResponse
  doAssert result.endsWith(specNote)
  echo "[OK] truncateMessage with spec note under limit"

proc testFormatStatusNotRunningNotPaused() =
  ## Verify status shows not running and not paused with zero ticket counts.
  let tmp = getTempDir() / "chat_status_basic"
  makeTestRepo(tmp)
  defer: cleanupTestRepo(tmp)
  createDir(tmp / ManagedStateDirName)

  setupPlanBranch(tmp, proc(planDir: string) =
    createDir(planDir / "tickets" / "open")
    createDir(planDir / "tickets" / "in-progress")
    createDir(planDir / "tickets" / "done")
    createDir(planDir / "tickets" / "stuck")
    createDir(planDir / "queue" / "merge" / "pending")
    writeFile(planDir / "tickets" / "open" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "in-progress" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "done" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "stuck" / ".gitkeep", "")
    writeFile(planDir / "queue" / "merge" / "pending" / ".gitkeep", "")
  )

  let result = formatStatusMessage(tmp, TestCaller)
  doAssert "**Orchestrator running:** no" in result
  doAssert "**Paused:** no" in result
  doAssert "Open: 0" in result
  doAssert "In-Progress: 0" in result
  doAssert "Done: 0" in result
  doAssert "Stuck: 0" in result
  doAssert "**Active agent:** none" in result
  echo "[OK] formatStatusMessage not running, not paused, zero tickets"

proc testFormatStatusRunning() =
  ## Verify status shows running when PID file exists.
  let tmp = getTempDir() / "chat_status_running"
  makeTestRepo(tmp)
  defer: cleanupTestRepo(tmp)
  createDir(tmp / ManagedStateDirName)

  setupPlanBranch(tmp, proc(planDir: string) =
    createDir(planDir / "tickets" / "open")
    createDir(planDir / "tickets" / "in-progress")
    createDir(planDir / "tickets" / "done")
    createDir(planDir / "tickets" / "stuck")
    writeFile(planDir / "tickets" / "open" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "in-progress" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "done" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "stuck" / ".gitkeep", "")
  )

  let pidPath = orchestratorPidPath(tmp)
  writeFile(pidPath, "12345")
  defer: removeFile(pidPath)

  let result = formatStatusMessage(tmp, TestCaller)
  doAssert "**Orchestrator running:** yes" in result
  echo "[OK] formatStatusMessage running with PID file"

proc testFormatStatusPaused() =
  ## Verify status shows paused when pause flag exists.
  let tmp = getTempDir() / "chat_status_paused"
  makeTestRepo(tmp)
  defer: cleanupTestRepo(tmp)
  createDir(tmp / ManagedStateDirName)

  setupPlanBranch(tmp, proc(planDir: string) =
    createDir(planDir / "tickets" / "open")
    createDir(planDir / "tickets" / "in-progress")
    createDir(planDir / "tickets" / "done")
    createDir(planDir / "tickets" / "stuck")
    writeFile(planDir / "tickets" / "open" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "in-progress" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "done" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "stuck" / ".gitkeep", "")
  )

  writePauseFlag(tmp)

  let result = formatStatusMessage(tmp, TestCaller)
  doAssert "**Paused:** yes" in result
  echo "[OK] formatStatusMessage paused"

proc testFormatStatusTicketCounts() =
  ## Verify status includes correct ticket counts.
  let tmp = getTempDir() / "chat_status_counts"
  makeTestRepo(tmp)
  defer: cleanupTestRepo(tmp)
  createDir(tmp / ManagedStateDirName)

  setupPlanBranch(tmp, proc(planDir: string) =
    createDir(planDir / "tickets" / "open")
    createDir(planDir / "tickets" / "in-progress")
    createDir(planDir / "tickets" / "done")
    createDir(planDir / "tickets" / "stuck")
    writeFile(planDir / "tickets" / "open" / "0001-test-open.md", "# Open ticket")
    writeFile(planDir / "tickets" / "open" / "0002-another-open.md", "# Another open")
    writeFile(planDir / "tickets" / "in-progress" / "0003-in-progress.md", "# In progress\n**Worktree:** —")
    writeFile(planDir / "tickets" / "done" / "0004-done.md", "# Done ticket")
    writeFile(planDir / "tickets" / "stuck" / "0005-stuck.md", "# Stuck ticket")
    writeFile(planDir / "tickets" / "stuck" / "0006-stuck-too.md", "# Also stuck")
  )

  let result = formatStatusMessage(tmp, TestCaller)
  doAssert "Open: 2" in result
  doAssert "In-Progress: 1" in result
  doAssert "Done: 1" in result
  doAssert "Stuck: 2" in result
  echo "[OK] formatStatusMessage ticket counts"

proc testFormatStatusActiveAgentNone() =
  ## Verify status shows "none" when no active agent.
  let tmp = getTempDir() / "chat_status_no_agent"
  makeTestRepo(tmp)
  defer: cleanupTestRepo(tmp)
  createDir(tmp / ManagedStateDirName)

  setupPlanBranch(tmp, proc(planDir: string) =
    createDir(planDir / "tickets" / "open")
    createDir(planDir / "tickets" / "in-progress")
    createDir(planDir / "tickets" / "done")
    createDir(planDir / "tickets" / "stuck")
    writeFile(planDir / "tickets" / "open" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "in-progress" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "done" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "stuck" / ".gitkeep", "")
  )

  let result = formatStatusMessage(tmp, TestCaller)
  doAssert "**Active agent:** none" in result
  echo "[OK] formatStatusMessage active agent none"

proc testFormatStatusActiveAgent() =
  ## Verify status shows active ticket ID when active merge queue item exists.
  let tmp = getTempDir() / "chat_status_active_agent"
  makeTestRepo(tmp)
  defer: cleanupTestRepo(tmp)
  createDir(tmp / ManagedStateDirName)

  setupPlanBranch(tmp, proc(planDir: string) =
    createDir(planDir / "tickets" / "open")
    createDir(planDir / "tickets" / "in-progress")
    createDir(planDir / "tickets" / "done")
    createDir(planDir / "tickets" / "stuck")
    createDir(planDir / "queue" / "merge" / "pending")
    writeFile(planDir / "tickets" / "open" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "done" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "stuck" / ".gitkeep", "")

    let ticketContent = "# Test ticket\n**Worktree:** /tmp/fake-worktree"
    writeFile(planDir / "tickets" / "in-progress" / "0042-active-ticket.md", ticketContent)

    let pendingContent = "**Ticket:** tickets/in-progress/0042-active-ticket.md\n**Ticket ID:** 0042\n**Branch:** scriptorium/ticket-0042\n**Worktree:** /tmp/fake-worktree\n**Summary:** Test summary"
    writeFile(planDir / "queue" / "merge" / "pending" / "0042-active-ticket.md", pendingContent)
    writeFile(planDir / "queue" / "merge" / "active.md", "queue/merge/pending/0042-active-ticket.md")
  )

  let result = formatStatusMessage(tmp, TestCaller)
  doAssert "**Active agent:** 0042" in result
  echo "[OK] formatStatusMessage active agent with ticket ID"

proc testFormatStatusInProgressElapsed() =
  ## Verify status lists in-progress tickets with elapsed times.
  let tmp = getTempDir() / "chat_status_elapsed"
  makeTestRepo(tmp)
  defer: cleanupTestRepo(tmp)
  createDir(tmp / ManagedStateDirName)

  let fakeWorktree = getTempDir() / "chat_status_elapsed_wt"
  createDir(fakeWorktree)
  defer: removeDir(fakeWorktree)

  setupPlanBranch(tmp, proc(planDir: string) =
    createDir(planDir / "tickets" / "open")
    createDir(planDir / "tickets" / "in-progress")
    createDir(planDir / "tickets" / "done")
    createDir(planDir / "tickets" / "stuck")
    writeFile(planDir / "tickets" / "open" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "done" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "stuck" / ".gitkeep", "")

    let ticketContent = "# Elapsed ticket\n**Worktree:** " & fakeWorktree
    writeFile(planDir / "tickets" / "in-progress" / "0050-elapsed-test.md", ticketContent)
  )

  let result = formatStatusMessage(tmp, TestCaller)
  doAssert "**In-progress tickets:**" in result
  doAssert "0050" in result
  echo "[OK] formatStatusMessage in-progress elapsed times"

proc testFormatStatusWaitingTickets() =
  ## Verify status lists waiting tickets with dependency info.
  let tmp = getTempDir() / "chat_status_waiting"
  makeTestRepo(tmp)
  defer: cleanupTestRepo(tmp)
  createDir(tmp / ManagedStateDirName)

  setupPlanBranch(tmp, proc(planDir: string) =
    createDir(planDir / "tickets" / "open")
    createDir(planDir / "tickets" / "in-progress")
    createDir(planDir / "tickets" / "done")
    createDir(planDir / "tickets" / "stuck")
    writeFile(planDir / "tickets" / "done" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "stuck" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "in-progress" / ".gitkeep", "")

    let ticketContent = "# Waiting ticket\n**Depends:** 0098, 0099"
    writeFile(planDir / "tickets" / "open" / "0100-waiting-ticket.md", ticketContent)
  )

  let result = formatStatusMessage(tmp, TestCaller)
  doAssert "**Waiting:** 0100" in result
  doAssert "0098" in result
  doAssert "0099" in result
  echo "[OK] formatStatusMessage waiting tickets with dependencies"

proc testFormatStatusBlockedTickets() =
  ## Verify status lists tickets in a cycle as waiting after cycle auto-repair.
  ## Note: readOrchestratorStatus never populates blockedTickets (the field and
  ## formatStatusMessage branch for it exist but are unreachable). Cycles are
  ## auto-repaired by buildRepairedDependencyGraph, which breaks one edge. The
  ## ticket that retains its dependency shows as **Waiting:** instead.
  let tmp = getTempDir() / "chat_status_blocked"
  makeTestRepo(tmp)
  defer: cleanupTestRepo(tmp)
  createDir(tmp / ManagedStateDirName)

  setupPlanBranch(tmp, proc(planDir: string) =
    createDir(planDir / "tickets" / "open")
    createDir(planDir / "tickets" / "in-progress")
    createDir(planDir / "tickets" / "done")
    createDir(planDir / "tickets" / "stuck")
    writeFile(planDir / "tickets" / "done" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "stuck" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "in-progress" / ".gitkeep", "")

    writeFile(planDir / "tickets" / "open" / "0070-ticket-a.md", "# Ticket A\n**Depends:** 0071")
    writeFile(planDir / "tickets" / "open" / "0071-ticket-b.md", "# Ticket B\n**Depends:** 0070")
  )

  let result = formatStatusMessage(tmp, TestCaller)
  doAssert "**Waiting:** 0070" in result
  echo "[OK] formatStatusMessage cycle dependencies produce waiting tickets"

proc testFormatQueueEmpty() =
  ## Verify queue message with all lists empty.
  let tmp = getTempDir() / "chat_queue_empty"
  makeTestRepo(tmp)
  defer: cleanupTestRepo(tmp)
  createDir(tmp / ManagedStateDirName)

  setupPlanBranch(tmp, proc(planDir: string) =
    createDir(planDir / "tickets" / "open")
    createDir(planDir / "tickets" / "in-progress")
    createDir(planDir / "queue" / "merge" / "pending")
    writeFile(planDir / "tickets" / "open" / ".gitkeep", "")
    writeFile(planDir / "tickets" / "in-progress" / ".gitkeep", "")
    writeFile(planDir / "queue" / "merge" / "pending" / ".gitkeep", "")
  )

  let result = formatQueueMessage(tmp, TestCaller)
  doAssert "**Merge queue:** 0 item(s)" in result
  doAssert "**In-progress tickets:** 0" in result
  doAssert "**Open tickets:** 0" in result
  echo "[OK] formatQueueMessage empty"

proc testFormatQueueWithItems() =
  ## Verify queue message shows merge queue item and ticket lists.
  let tmp = getTempDir() / "chat_queue_items"
  makeTestRepo(tmp)
  defer: cleanupTestRepo(tmp)
  createDir(tmp / ManagedStateDirName)

  setupPlanBranch(tmp, proc(planDir: string) =
    createDir(planDir / "tickets" / "open")
    createDir(planDir / "tickets" / "in-progress")
    createDir(planDir / "queue" / "merge" / "pending")

    let pendingContent = "**Ticket:** tickets/in-progress/0010-merge-item.md\n**Ticket ID:** 0010\n**Branch:** scriptorium/ticket-0010\n**Worktree:** /tmp/wt-0010\n**Summary:** Fix the widget"
    writeFile(planDir / "queue" / "merge" / "pending" / "0010-merge-item.md", pendingContent)

    writeFile(planDir / "tickets" / "in-progress" / "0010-merge-item.md", "# Merge item ticket")
    writeFile(planDir / "tickets" / "in-progress" / "0011-other-wip.md", "# Other WIP")
    writeFile(planDir / "tickets" / "open" / "0020-open-ticket.md", "# Open ticket")
  )

  let result = formatQueueMessage(tmp, TestCaller)
  doAssert "**Merge queue:** 1 item(s)" in result
  doAssert "0010" in result
  doAssert "Fix the widget" in result
  doAssert "**In-progress tickets:** 2" in result
  doAssert "**Open tickets:** 1" in result
  doAssert "0020" in result
  echo "[OK] formatQueueMessage with items"

proc testFormatQueueMultipleItems() =
  ## Verify queue message with multiple open and in-progress tickets.
  let tmp = getTempDir() / "chat_queue_multi"
  makeTestRepo(tmp)
  defer: cleanupTestRepo(tmp)
  createDir(tmp / ManagedStateDirName)

  setupPlanBranch(tmp, proc(planDir: string) =
    createDir(planDir / "tickets" / "open")
    createDir(planDir / "tickets" / "in-progress")
    createDir(planDir / "queue" / "merge" / "pending")
    writeFile(planDir / "queue" / "merge" / "pending" / ".gitkeep", "")

    writeFile(planDir / "tickets" / "in-progress" / "0030-wip-a.md", "# WIP A")
    writeFile(planDir / "tickets" / "in-progress" / "0031-wip-b.md", "# WIP B")
    writeFile(planDir / "tickets" / "open" / "0040-open-a.md", "# Open A")
    writeFile(planDir / "tickets" / "open" / "0041-open-b.md", "# Open B")
    writeFile(planDir / "tickets" / "open" / "0042-open-c.md", "# Open C")
  )

  let result = formatQueueMessage(tmp, TestCaller)
  doAssert "**Merge queue:** 0 item(s)" in result
  doAssert "**In-progress tickets:** 2" in result
  doAssert "0030" in result
  doAssert "0031" in result
  doAssert "**Open tickets:** 3" in result
  doAssert "0040" in result
  doAssert "0041" in result
  doAssert "0042" in result
  echo "[OK] formatQueueMessage multiple items"

testParseChatModeAsk()
testParseChatModePlan()
testParseChatModeDo()
testParseChatModeDefault()
testParseChatModeCaseInsensitive()
testParseChatModeWhitespace()
testChatModeEnumValues()
testTruncateMessageUnderLimit()
testTruncateMessageAtLimit()
testTruncateMessageOverLimit()
testTruncateMessageCustomLimit()
testHandleHelp()
testHandlePauseNotPaused()
testHandlePauseAlreadyPaused()
testHandleResumeWhenPaused()
testHandleResumeWhenNotPaused()
testTruncateMessageWithSpecNote()
testTruncateMessageWithSpecNoteUnderLimit()
testFormatStatusNotRunningNotPaused()
testFormatStatusRunning()
testFormatStatusPaused()
testFormatStatusTicketCounts()
testFormatStatusActiveAgentNone()
testFormatStatusActiveAgent()
testFormatStatusInProgressElapsed()
testFormatStatusWaitingTickets()
testFormatStatusBlockedTickets()
testFormatQueueEmpty()
testFormatQueueWithItems()
testFormatQueueMultipleItems()
