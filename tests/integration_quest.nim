## Integration tests for scriptorium quest mode.

import
  std/[os, strutils, unittest],
  scriptorium/[agent_runner, config, orchestrator, quest_system, shared_state],
  helpers

suite "scriptorium quest":
  setup:
    tickSleepOverrideMs = 0

  teardown:
    tickSleepOverrideMs = -1

  test "quest eval declares done and orchestrator exits":
    let tmp = getTempDir() / "scriptorium_test_quest_done"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    writeOrchestratorEndpointConfig(tmp, 30)

    startQuest(tmp, "ensure hello.txt exists with content world")

    var questCalls = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Simulate an architect that declares the quest done on the first eval.
      if request.ticketId == "quest":
        inc questCalls
        writeFile(
          request.workingDir / "quests" / "active-verdict.json",
          """{"done": true, "reason": "world spotted", "iteration": 1}""",
        )
        return AgentRunResult(
          backend: harnessCodex, exitCode: 0, attempt: 1, attemptCount: 1,
          lastMessage: "done", timeoutKind: "none",
        )
      return AgentRunResult(
        backend: harnessCodex, exitCode: 0, attempt: 1, attemptCount: 1,
        lastMessage: "noop", timeoutKind: "none",
      )

    runOrchestratorForTicks(tmp, 10, fakeRunner, questMode = true)

    check questCalls == 1
    check shouldRun == false

    let finalVerdict = latestQuestVerdict(tmp)
    check finalVerdict.done == true
    check finalVerdict.reason == "world spotted"
    check finalVerdict.iteration == 1

    archiveQuest(tmp, finalVerdict)
    let filesAfterArchive = planTreeFiles(tmp)
    check "quests/active.md" notin filesAfterArchive
    check "quests/active-verdict.json" notin filesAfterArchive
    let archived = filesAfterArchive.filterIt(it.startsWith("quests/done/") and it.endsWith(".md"))
    check archived.len == 1

  test "quest eval keeps running when verdict is not done":
    let tmp = getTempDir() / "scriptorium_test_quest_not_done"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    addPassingMakefile(tmp)
    writeOrchestratorEndpointConfig(tmp, 31)

    startQuest(tmp, "drive a hard goal")

    var questCalls = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Architect writes a not-done verdict each iteration; quest keeps spinning.
      if request.ticketId == "quest":
        inc questCalls
        writeFile(
          request.workingDir / "quests" / "active-verdict.json",
          """{"done": false, "reason": "still missing X", "iteration": ##}""".replace("##", $questCalls),
        )
        return AgentRunResult(
          backend: harnessCodex, exitCode: 0, attempt: 1, attemptCount: 1,
          lastMessage: "iterate", timeoutKind: "none",
        )
      return AgentRunResult(
        backend: harnessCodex, exitCode: 0, attempt: 1, attemptCount: 1,
        lastMessage: "noop", timeoutKind: "none",
      )

    runOrchestratorForTicks(tmp, 3, fakeRunner, questMode = true)

    check questCalls >= 1
    let latest = latestQuestVerdict(tmp)
    check latest.done == false
    check "still missing" in latest.reason

  test "startQuest refuses to overwrite an active quest":
    let tmp = getTempDir() / "scriptorium_test_quest_singleflight"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    writeOrchestratorEndpointConfig(tmp, 32)

    startQuest(tmp, "first quest")
    var raised = false
    try:
      startQuest(tmp, "second quest")
    except ValueError:
      raised = true
    check raised

    let files = planTreeFiles(tmp)
    check "quests/active.md" in files

  test "archiveQuest moves active files into quests/done":
    let tmp = getTempDir() / "scriptorium_test_quest_archive"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    writeOrchestratorEndpointConfig(tmp, 33)

    startQuest(tmp, "archive me")
    archiveQuest(tmp,
      QuestVerdict(done: true, reason: "ok", iteration: 2))

    let files = planTreeFiles(tmp)
    check "quests/active.md" notin files
    check "quests/active-verdict.json" notin files
    let archived = files.filterIt(it.startsWith("quests/done/") and it.endsWith(".md"))
    check archived.len == 1
    let archiveContent = readPlanFile(tmp, archived[0])
    check "archive me" in archiveContent
    check "Status:** done" in archiveContent
