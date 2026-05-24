import
  std/[json, os, strutils],
  scriptorium/[prompt_builders, quest_system]

proc testParseQuestVerdictDone() =
  ## Verify parseQuestVerdict parses a well-formed done verdict.
  let raw = """{"done": true, "reason": "all good", "iteration": 3}"""
  let v = parseQuestVerdict(raw)
  doAssert v.done == true
  doAssert v.reason == "all good"
  doAssert v.iteration == 3
  echo "[OK] parseQuestVerdict parses done=true"

proc testParseQuestVerdictNotDone() =
  ## Verify parseQuestVerdict parses a well-formed not-done verdict.
  let raw = """{"done": false, "reason": "missing X", "iteration": 1}"""
  let v = parseQuestVerdict(raw)
  doAssert v.done == false
  doAssert v.reason == "missing X"
  doAssert v.iteration == 1
  echo "[OK] parseQuestVerdict parses done=false"

proc testParseQuestVerdictMalformed() =
  ## Verify parseQuestVerdict raises on malformed JSON.
  var raised = false
  try:
    discard parseQuestVerdict("{not json")
  except CatchableError:
    raised = true
  doAssert raised
  echo "[OK] parseQuestVerdict raises on malformed JSON"

proc testParseQuestVerdictEmpty() =
  ## Verify parseQuestVerdict raises on empty content.
  var raised = false
  try:
    discard parseQuestVerdict("   ")
  except CatchableError:
    raised = true
  doAssert raised
  echo "[OK] parseQuestVerdict raises on empty content"

proc testIsQuestActiveFalse() =
  ## Verify isQuestActive returns false on a fresh directory.
  let tmpDir = getTempDir() / "test_quest_active_false"
  if dirExists(tmpDir): removeDir(tmpDir)
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  doAssert isQuestActive(tmpDir) == false
  echo "[OK] isQuestActive returns false when no active quest exists"

proc testIsQuestActiveTrue() =
  ## Verify isQuestActive returns true once an active quest file exists.
  let tmpDir = getTempDir() / "test_quest_active_true"
  if dirExists(tmpDir): removeDir(tmpDir)
  createDir(tmpDir / "quests")
  writeFile(tmpDir / "quests" / "active.md", "do a thing")
  defer: removeDir(tmpDir)

  doAssert isQuestActive(tmpDir) == true
  echo "[OK] isQuestActive returns true when active quest file exists"

proc testWriteAndReadActiveQuest() =
  ## Verify writeQuestActiveFile and readActiveQuest round-trip the prompt.
  let tmpDir = getTempDir() / "test_quest_write_read"
  if dirExists(tmpDir): removeDir(tmpDir)
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  writeQuestActiveFile(tmpDir, "make a hello world")
  doAssert isQuestActive(tmpDir)
  doAssert readActiveQuest(tmpDir) == "make a hello world"
  echo "[OK] writeQuestActiveFile + readActiveQuest round-trip"

proc testListAndNextVerdictNumberEmpty() =
  ## Verify nextVerdictNumber returns 1 on a fresh directory.
  let tmpDir = getTempDir() / "test_quest_next_empty"
  if dirExists(tmpDir): removeDir(tmpDir)
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  doAssert listVerdictFiles(tmpDir).len == 0
  doAssert nextVerdictNumber(tmpDir) == 1
  echo "[OK] nextVerdictNumber returns 1 on empty verdicts dir"

proc testNextVerdictNumberWithFiles() =
  ## Verify nextVerdictNumber returns highest + 1 across existing files.
  let tmpDir = getTempDir() / "test_quest_next_with"
  if dirExists(tmpDir): removeDir(tmpDir)
  createDir(tmpDir / "quests" / "verdicts")
  defer: removeDir(tmpDir)

  writeFile(tmpDir / "quests" / "verdicts" / "001.json", "{}")
  writeFile(tmpDir / "quests" / "verdicts" / "003.json", "{}")
  doAssert nextVerdictNumber(tmpDir) == 4
  echo "[OK] nextVerdictNumber returns highest + 1"

proc testReadRecentVerdictsEmpty() =
  ## Verify readRecentVerdicts returns a placeholder when no verdicts exist.
  let tmpDir = getTempDir() / "test_quest_recent_empty"
  if dirExists(tmpDir): removeDir(tmpDir)
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let recent = readRecentVerdicts(tmpDir)
  doAssert "No prior verdicts" in recent
  echo "[OK] readRecentVerdicts returns placeholder when empty"

proc testReadRecentVerdictsExists() =
  ## Verify readRecentVerdicts returns content from the most recent N files.
  let tmpDir = getTempDir() / "test_quest_recent_exists"
  if dirExists(tmpDir): removeDir(tmpDir)
  createDir(tmpDir / "quests" / "verdicts")
  defer: removeDir(tmpDir)

  writeFile(tmpDir / "quests" / "verdicts" / "001.json",
    """{"done":false,"reason":"step one","iteration":1}""")
  writeFile(tmpDir / "quests" / "verdicts" / "002.json",
    """{"done":false,"reason":"step two","iteration":2}""")
  let recent = readRecentVerdicts(tmpDir, 5)
  doAssert "step one" in recent
  doAssert "step two" in recent
  doAssert "001.json" in recent
  doAssert "002.json" in recent
  echo "[OK] readRecentVerdicts returns content from existing verdict files"

proc testBuildTicketSummary() =
  ## Verify buildTicketSummary reports counts across all ticket directories.
  let tmpDir = getTempDir() / "test_quest_ticket_summary"
  if dirExists(tmpDir): removeDir(tmpDir)
  createDir(tmpDir / "tickets" / "open")
  createDir(tmpDir / "tickets" / "in-progress")
  createDir(tmpDir / "tickets" / "done")
  createDir(tmpDir / "tickets" / "stuck")
  defer: removeDir(tmpDir)

  writeFile(tmpDir / "tickets" / "open" / "0001-a.md", "x")
  writeFile(tmpDir / "tickets" / "open" / "0002-b.md", "x")
  writeFile(tmpDir / "tickets" / "done" / "0003-c.md", "x")
  let summary = buildTicketSummary(tmpDir)
  doAssert "open: 2" in summary
  doAssert "in-progress: 0" in summary
  doAssert "done: 1" in summary
  doAssert "stuck: 0" in summary
  echo "[OK] buildTicketSummary reports per-state ticket counts"

proc testSlugifyPrompt() =
  ## Verify slugifyPrompt produces a filesystem-safe slug.
  doAssert slugifyPrompt("Hello World!") == "hello-world"
  doAssert slugifyPrompt("  multiple   spaces  ") == "multiple-spaces"
  doAssert slugifyPrompt("###") == "quest"
  doAssert slugifyPrompt("a_very_long_prompt_that_should_be_truncated_to_some_reasonable_length").len <= 40
  echo "[OK] slugifyPrompt produces filesystem-safe slugs"

proc testBuildArchitectQuestPromptContents() =
  ## Verify buildArchitectQuestPrompt embeds all placeholders.
  let prompt = buildArchitectQuestPrompt(
    "/repo",
    "/plan",
    "ship feature X",
    4,
    "## prior\nNo prior verdicts.",
    "- open: 1\n- in-progress: 0\n- done: 2\n- stuck: 0",
  )
  doAssert "ship feature X" in prompt
  doAssert "Iteration 4" in prompt
  doAssert "open: 1" in prompt
  doAssert "active-verdict.json" in prompt
  doAssert "/repo" in prompt
  doAssert "/plan" in prompt
  echo "[OK] buildArchitectQuestPrompt includes prompt, iteration, summary, paths"

when isMainModule:
  testParseQuestVerdictDone()
  testParseQuestVerdictNotDone()
  testParseQuestVerdictMalformed()
  testParseQuestVerdictEmpty()
  testIsQuestActiveFalse()
  testIsQuestActiveTrue()
  testWriteAndReadActiveQuest()
  testListAndNextVerdictNumberEmpty()
  testNextVerdictNumberWithFiles()
  testReadRecentVerdictsEmpty()
  testReadRecentVerdictsExists()
  testBuildTicketSummary()
  testSlugifyPrompt()
  testBuildArchitectQuestPromptContents()
