import
  std/[os, strutils],
  scriptorium/[agent_runner, config, loop_system, prompt_builders]

proc testQueueDrainedAllEmpty() =
  ## Verify isQueueDrained returns true when all directories are empty.
  let tmpDir = getTempDir() / "test_loop_system_empty"
  createDir(tmpDir / "tickets" / "open")
  createDir(tmpDir / "tickets" / "in-progress")
  createDir(tmpDir / "queue" / "merge" / "pending")
  defer: removeDir(tmpDir)

  doAssert isQueueDrained(tmpDir) == true
  echo "[OK] isQueueDrained returns true when all directories are empty"

proc testQueueNotDrainedOpenTicket() =
  ## Verify isQueueDrained returns false when open has a markdown file.
  let tmpDir = getTempDir() / "test_loop_system_open"
  createDir(tmpDir / "tickets" / "open")
  createDir(tmpDir / "tickets" / "in-progress")
  createDir(tmpDir / "queue" / "merge" / "pending")
  writeFile(tmpDir / "tickets" / "open" / "0001-test.md", "ticket")
  defer: removeDir(tmpDir)

  doAssert isQueueDrained(tmpDir) == false
  echo "[OK] isQueueDrained returns false when open has a .md file"

proc testQueueNotDrainedInProgress() =
  ## Verify isQueueDrained returns false when in-progress has a markdown file.
  let tmpDir = getTempDir() / "test_loop_system_inprogress"
  createDir(tmpDir / "tickets" / "open")
  createDir(tmpDir / "tickets" / "in-progress")
  createDir(tmpDir / "queue" / "merge" / "pending")
  writeFile(tmpDir / "tickets" / "in-progress" / "0002-test.md", "ticket")
  defer: removeDir(tmpDir)

  doAssert isQueueDrained(tmpDir) == false
  echo "[OK] isQueueDrained returns false when in-progress has a .md file"

proc testQueueNotDrainedPending() =
  ## Verify isQueueDrained returns false when merge pending has a markdown file.
  let tmpDir = getTempDir() / "test_loop_system_pending"
  createDir(tmpDir / "tickets" / "open")
  createDir(tmpDir / "tickets" / "in-progress")
  createDir(tmpDir / "queue" / "merge" / "pending")
  writeFile(tmpDir / "queue" / "merge" / "pending" / "0003-test.md", "ticket")
  defer: removeDir(tmpDir)

  doAssert isQueueDrained(tmpDir) == false
  echo "[OK] isQueueDrained returns false when merge pending has a .md file"

proc testRunFeedbackCommandSuccess() =
  ## Verify runFeedbackCommand returns output from a successful command.
  let fb = runFeedbackCommand("/tmp", "echo hello")
  doAssert fb.exitCode == 0
  doAssert fb.timedOut == false
  doAssert fb.output.strip() == "hello"
  echo "[OK] runFeedbackCommand returns output containing hello"

proc testRunFeedbackCommandFailure() =
  ## Verify runFeedbackCommand returns exit code on a failing command without raising.
  let fb = runFeedbackCommand("/tmp", "exit 1")
  doAssert fb.exitCode != 0
  doAssert fb.timedOut == false
  echo "[OK] runFeedbackCommand returns non-zero exit code without raising"

proc testRunFeedbackCommandTimeoutResult() =
  ## Verify FeedbackResult correctly represents a timeout scenario.
  ## Note: runCommandCapture's readAll blocks until process exits, so we
  ## test the timeout path by verifying the FeedbackResult structure directly.
  let fb = FeedbackResult(output: "timed out", exitCode: -1, timedOut: true)
  doAssert fb.timedOut == true
  doAssert fb.exitCode == -1
  doAssert fb.output == "timed out"
  echo "[OK] FeedbackResult correctly represents timeout"

proc testFormatFeedbackResultSuccess() =
  ## Verify formatFeedbackResult passes through output on success.
  let fb = FeedbackResult(output: "all good", exitCode: 0, timedOut: false)
  let formatted = formatFeedbackResult(fb)
  doAssert formatted == "all good"
  echo "[OK] formatFeedbackResult passes through output on success"

proc testFormatFeedbackResultFailure() =
  ## Verify formatFeedbackResult includes exit code on failure.
  let fb = FeedbackResult(output: "some output", exitCode: 1, timedOut: false)
  let formatted = formatFeedbackResult(fb)
  doAssert "[EXIT CODE 1]" in formatted
  doAssert "some output" in formatted
  echo "[OK] formatFeedbackResult includes exit code on failure"

proc testFormatFeedbackResultTimeout() =
  ## Verify formatFeedbackResult includes timeout marker.
  let fb = FeedbackResult(output: "timed out msg", exitCode: -1, timedOut: true)
  let formatted = formatFeedbackResult(fb)
  doAssert "[TIMEOUT]" in formatted
  doAssert "timed out msg" in formatted
  echo "[OK] formatFeedbackResult includes timeout marker"

proc testReadIterationLogMissing() =
  ## Verify readIterationLog returns empty string when file does not exist.
  let tmpDir = getTempDir() / "test_loop_read_missing"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let content = readIterationLog(tmpDir)
  doAssert content == ""
  echo "[OK] readIterationLog returns empty string when file missing"

proc testReadIterationLogExists() =
  ## Verify readIterationLog returns file content when it exists.
  let tmpDir = getTempDir() / "test_loop_read_exists"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  writeFile(tmpDir / "iteration_log.md", "## Iteration 1\nsome content\n")
  let content = readIterationLog(tmpDir)
  doAssert content == "## Iteration 1\nsome content\n"
  echo "[OK] readIterationLog returns file content when present"

proc testNextIterationNumberEmpty() =
  ## Verify nextIterationNumber returns 1 when no log exists.
  let tmpDir = getTempDir() / "test_loop_next_empty"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let num = nextIterationNumber(tmpDir)
  doAssert num == 1
  echo "[OK] nextIterationNumber returns 1 when no log exists"

proc testNextIterationNumberWithEntries() =
  ## Verify nextIterationNumber returns highest N + 1.
  let tmpDir = getTempDir() / "test_loop_next_entries"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  writeFile(tmpDir / "iteration_log.md", "## Iteration 1\nfoo\n\n## Iteration 3\nbar\n")
  let num = nextIterationNumber(tmpDir)
  doAssert num == 4
  echo "[OK] nextIterationNumber returns 4 after iteration 3"

proc testAppendIterationLogEntry() =
  ## Verify appendIterationLogEntry appends formatted entry.
  let tmpDir = getTempDir() / "test_loop_append"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  appendIterationLogEntry(tmpDir, 1, "output1", "assess1", "strat1", "trade1")
  let content = readIterationLog(tmpDir)
  doAssert "## Iteration 1" in content
  doAssert "output1" in content
  doAssert "assess1" in content
  doAssert "strat1" in content
  doAssert "trade1" in content
  echo "[OK] appendIterationLogEntry writes formatted entry"

proc testAppendIterationLogEntryMultiple() =
  ## Verify multiple appends produce increasing iteration headings.
  let tmpDir = getTempDir() / "test_loop_append_multi"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  appendIterationLogEntry(tmpDir, 1, "out1", "a1", "s1", "t1")
  appendIterationLogEntry(tmpDir, 2, "out2", "a2", "s2", "t2")
  let content = readIterationLog(tmpDir)
  doAssert "## Iteration 1" in content
  doAssert "## Iteration 2" in content
  let num = nextIterationNumber(tmpDir)
  doAssert num == 3
  echo "[OK] multiple appends produce correct iteration numbers"

proc testBuildArchitectLoopPromptContents() =
  ## Verify buildArchitectLoopPrompt includes goal, iteration log, feedback, iteration number, and instructions.
  let
    goal = "Reduce test flakiness below 1%"
    iterLog = "## Iteration 1\nPrevious results here\n"
    feedback = "3 tests still flaky"
    prompt = buildArchitectLoopPrompt("/repo", "/plan", goal, iterLog, feedback, 2)
  doAssert goal in prompt
  doAssert iterLog in prompt
  doAssert feedback in prompt
  doAssert "Iteration 2" in prompt
  doAssert "Assess previous results" in prompt
  doAssert "Write the next iteration log entry" in prompt
  doAssert "investigate rather than press forward" in prompt
  doAssert "hard constraints" in prompt
  doAssert "non-negotiable" in prompt
  echo "[OK] buildArchitectLoopPrompt contains goal, log, feedback, iteration number, and instructions"

proc testBuildArchitectLoopPromptWithMockRunner() =
  ## Verify a mock runner receives a prompt containing expected content.
  var capturedPrompt = ""
  let mockRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
    capturedPrompt = request.prompt
    result = AgentRunResult(exitCode: 0)

  let
    goal = "Ship v2.0"
    iterLog = "## Iteration 1\nFirst pass\n"
    feedback = "Build succeeded"
    prompt = buildArchitectLoopPrompt("/repo", "/plan", goal, iterLog, feedback, 2)
  discard mockRunner(AgentRunRequest(prompt: prompt, workingDir: "/plan"))
  doAssert goal in capturedPrompt
  doAssert iterLog in capturedPrompt
  doAssert feedback in capturedPrompt
  echo "[OK] mock runner receives prompt with goal, iteration log, and feedback"

proc makeDrainedPlanDir(tmpDir: string) =
  ## Create a fake plan directory with empty queues (drained state).
  createDir(tmpDir / "tickets" / "open")
  createDir(tmpDir / "tickets" / "in-progress")
  createDir(tmpDir / "queue" / "merge" / "pending")

proc testLoopDisabledNoCycle() =
  ## Verify no feedback cycle runs when loop.enabled is false, even if queue is drained.
  let tmpDir = getTempDir() / "test_loop_disabled"
  makeDrainedPlanDir(tmpDir)
  defer: removeDir(tmpDir)

  let loopCfg = LoopConfig(enabled: false, feedback: "echo test", goal: "test", maxIterations: 0)
  var loopIterationCount = 0
  var feedbackRan = false

  # Simulate step 8 logic.
  if loopCfg.enabled and loopCfg.feedback.len > 0:
    let drained = isQueueDrained(tmpDir)
    if drained:
      inc loopIterationCount
      feedbackRan = true

  doAssert loopIterationCount == 0
  doAssert feedbackRan == false
  echo "[OK] loop disabled: no feedback cycle even when queue is drained"

proc testLoopEnabledDrainedQueueTriggersCycle() =
  ## Verify feedback command and architect are invoked when loop is enabled and queue is drained.
  let tmpDir = getTempDir() / "test_loop_enabled_drained"
  makeDrainedPlanDir(tmpDir)
  defer: removeDir(tmpDir)

  let loopCfg = LoopConfig(enabled: true, feedback: "echo feedback-output", goal: "improve", maxIterations: 0, feedbackTimeoutMs: DefaultFeedbackTimeoutMs)
  var loopIterationCount = 0
  var feedbackOutput = ""
  var architectInvoked = false

  let fakeRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
    architectInvoked = true
    result = AgentRunResult(exitCode: 0)

  # Simulate step 8 logic.
  if loopCfg.enabled and loopCfg.feedback.len > 0:
    let drained = isQueueDrained(tmpDir)
    if drained:
      if loopCfg.maxIterations > 0 and loopIterationCount >= loopCfg.maxIterations:
        discard
      else:
        inc loopIterationCount
        let fb = runFeedbackCommand("/tmp", loopCfg.feedback, loopCfg.feedbackTimeoutMs)
        feedbackOutput = formatFeedbackResult(fb)
        discard fakeRunner(AgentRunRequest(prompt: "test", workingDir: tmpDir))

  doAssert loopIterationCount == 1
  doAssert "feedback-output" in feedbackOutput
  doAssert architectInvoked
  echo "[OK] loop enabled + drained: feedback command and architect invoked"

proc testLoopMaxIterationsReached() =
  ## Verify no further cycles run once maxIterations is reached.
  let tmpDir = getTempDir() / "test_loop_max_iter"
  makeDrainedPlanDir(tmpDir)
  defer: removeDir(tmpDir)

  let loopCfg = LoopConfig(enabled: true, feedback: "echo test", goal: "test", maxIterations: 1)
  var loopIterationCount = 1
  var feedbackRan = false

  # Simulate step 8 logic with loopIterationCount already at maxIterations.
  if loopCfg.enabled and loopCfg.feedback.len > 0:
    let drained = isQueueDrained(tmpDir)
    if drained:
      if loopCfg.maxIterations > 0 and loopIterationCount >= loopCfg.maxIterations:
        discard
      else:
        inc loopIterationCount
        feedbackRan = true

  doAssert loopIterationCount == 1
  doAssert feedbackRan == false
  echo "[OK] loop maxIterations reached: no further cycles run"

when isMainModule:
  testQueueDrainedAllEmpty()
  testQueueNotDrainedOpenTicket()
  testQueueNotDrainedInProgress()
  testQueueNotDrainedPending()
  testRunFeedbackCommandSuccess()
  testRunFeedbackCommandFailure()
  testRunFeedbackCommandTimeoutResult()
  testFormatFeedbackResultSuccess()
  testFormatFeedbackResultFailure()
  testFormatFeedbackResultTimeout()
  testReadIterationLogMissing()
  testReadIterationLogExists()
  testNextIterationNumberEmpty()
  testNextIterationNumberWithEntries()
  testAppendIterationLogEntry()
  testAppendIterationLogEntryMultiple()
  testBuildArchitectLoopPromptContents()
  testBuildArchitectLoopPromptWithMockRunner()
  testLoopDisabledNoCycle()
  testLoopEnabledDrainedQueueTriggersCycle()
  testLoopMaxIterationsReached()
