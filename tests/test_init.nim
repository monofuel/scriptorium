import
  std/[json, os, osproc, strutils],
  scriptorium/init

const
  SpecPlaceholder = "# Spec\n\nRun `scriptorium plan` to build your spec with the Architect.\n"
  ExpectedDirs = [
    "areas",
    "docs",
    "docs/iterations",
    "services",
    "tickets/open",
    "tickets/in-progress",
    "tickets/done",
    "tickets/stuck",
    "decisions",
  ]

proc createTempRepo(): string =
  ## Create a temporary git repo with an initial commit on master.
  result = getTempDir() / "test_init_" & $getCurrentProcessId()
  createDir(result)
  let qpath = quoteShell(result)
  discard execCmdEx("git init " & qpath)
  discard execCmdEx("git -C " & qpath & " config user.email test@test.com")
  discard execCmdEx("git -C " & qpath & " config user.name Test")
  discard execCmdEx("git -C " & qpath & " checkout -b master")
  writeFile(result / "README.md", "test\n")
  discard execCmdEx("git -C " & qpath & " add .")
  discard execCmdEx("git -C " & qpath & " commit -m init")

proc testNotAGitRepo() =
  ## Verify runInit raises ValueError on a non-git directory.
  let tmpDir = getTempDir() / "test_init_nogit_" & $getCurrentProcessId()
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  var raised = false
  try:
    runInit(tmpDir, quiet = true)
  except ValueError:
    raised = true
  doAssert raised, "expected ValueError for non-git directory"
  echo "[OK] runInit raises ValueError on non-git directory"

proc testAlreadyInitializedFails() =
  ## Verify runInit raises ValueError when scriptorium/plan branch already exists.
  let repo = createTempRepo()
  defer: removeDir(repo)

  let qpath = quoteShell(repo)
  discard execCmdEx("git -C " & qpath & " branch scriptorium/plan")

  var raised = false
  try:
    runInit(repo, quiet = true)
  except ValueError:
    raised = true
  doAssert raised, "expected ValueError when plan branch already exists"
  echo "[OK] runInit raises ValueError when plan branch already exists"

proc testSuccessfulInit() =
  ## Verify runInit creates plan branch with expected directories and spec.md.
  let repo = createTempRepo()
  defer: removeDir(repo)

  runInit(repo, quiet = true)

  let qpath = quoteShell(repo)
  let (_, branchRc) = execCmdEx(
    "git -C " & qpath & " rev-parse --verify scriptorium/plan"
  )
  doAssert branchRc == 0, "scriptorium/plan branch should exist"

  for d in ExpectedDirs:
    let (_, fileRc) = execCmdEx(
      "git -C " & qpath & " show scriptorium/plan:" & d & "/.gitkeep"
    )
    doAssert fileRc == 0, "expected " & d & "/.gitkeep on plan branch"

  let (_, specRc) = execCmdEx(
    "git -C " & qpath & " show scriptorium/plan:spec.md"
  )
  doAssert specRc == 0, "spec.md should exist on plan branch"
  echo "[OK] runInit creates plan branch with expected structure"

proc testSpecPlaceholderContent() =
  ## Verify spec.md contains the exact placeholder text.
  let repo = createTempRepo()
  defer: removeDir(repo)

  runInit(repo, quiet = true)

  let qpath = quoteShell(repo)
  let (specOut, specRc) = execCmdEx(
    "git -C " & qpath & " show scriptorium/plan:spec.md"
  )
  doAssert specRc == 0, "spec.md should exist on plan branch"
  doAssert specOut == SpecPlaceholder, "spec.md content mismatch: got " & repr(specOut)
  echo "[OK] spec.md placeholder content matches expected text"

proc testDoubleInitFails() =
  ## Verify running init twice raises ValueError on the second call.
  let repo = createTempRepo()
  defer: removeDir(repo)

  runInit(repo, quiet = true)

  var raised = false
  try:
    runInit(repo, quiet = true)
  except ValueError:
    raised = true
  doAssert raised, "expected ValueError on second init"
  echo "[OK] double init raises ValueError"

proc testInitNoRemote() =
  ## Verify init works on a repo with no remote configured.
  let repo = createTempRepo()
  defer: removeDir(repo)

  # No remote — should not crash, should fall back to "master".
  runInit(repo, quiet = true)

  let qpath = quoteShell(repo)
  let (_, branchRc) = execCmdEx(
    "git -C " & qpath & " rev-parse --verify scriptorium/plan"
  )
  doAssert branchRc == 0, "scriptorium/plan branch should exist"
  echo "[OK] init works on repo with no remote"

proc testMakefileContainsAllTargets() =
  ## Verify the Makefile created by runInit contains all four required targets.
  let repo = createTempRepo()
  defer: removeDir(repo)

  runInit(repo, quiet = true)

  let content = readFile(repo / "Makefile")
  const RequiredTargets = ["test", "build", "integration-test", "e2e-test"]
  for target in RequiredTargets:
    let targetLine = target & ":"
    doAssert targetLine in content, "Makefile missing target: " & target
  doAssert ".PHONY:" in content, "Makefile missing .PHONY declaration"
  for target in RequiredTargets:
    let phonyLine = content.splitLines()[0]
    doAssert target in phonyLine, ".PHONY missing target: " & target
  echo "[OK] Makefile contains all four required targets"

proc testSrcAndDocsCreated() =
  ## Verify runInit creates src/.gitkeep and docs/.gitkeep.
  let repo = createTempRepo()
  defer: removeDir(repo)

  runInit(repo, quiet = true)

  doAssert fileExists(repo / "src" / ".gitkeep"), "src/.gitkeep should exist"
  doAssert fileExists(repo / "docs" / ".gitkeep"), "docs/.gitkeep should exist"
  echo "[OK] runInit creates src/.gitkeep and docs/.gitkeep"

proc testAgentsMdCreated() =
  ## Verify runInit creates AGENTS.md with non-empty content.
  let repo = createTempRepo()
  defer: removeDir(repo)

  runInit(repo, quiet = true)

  let agentsPath = repo / "AGENTS.md"
  doAssert fileExists(agentsPath), "AGENTS.md should exist after init"
  let content = readFile(agentsPath)
  doAssert content.len > 0, "AGENTS.md should be non-empty"
  echo "[OK] runInit creates AGENTS.md with content"

proc testConfigJsonCreated() =
  ## Verify runInit creates scriptorium.json with valid JSON and expected keys.
  let repo = createTempRepo()
  defer: removeDir(repo)

  runInit(repo, quiet = true)

  let configPath = repo / "scriptorium.json"
  doAssert fileExists(configPath), "scriptorium.json should exist after init"
  let content = readFile(configPath)
  let node = parseJson(content)
  const ExpectedKeys = ["agents", "concurrency", "endpoints", "logLevel"]
  for key in ExpectedKeys:
    doAssert node.hasKey(key), "scriptorium.json missing key: " & key
  echo "[OK] runInit creates scriptorium.json with valid JSON and expected keys"

proc testGitignoreEntry() =
  ## Verify .gitignore contains a .scriptorium entry after init.
  let repo = createTempRepo()
  defer: removeDir(repo)

  runInit(repo, quiet = true)

  let gitignorePath = repo / ".gitignore"
  doAssert fileExists(gitignorePath), ".gitignore should exist after init"
  let content = readFile(gitignorePath)
  doAssert ".scriptorium/" in content, ".gitignore should contain .scriptorium/ entry"
  echo "[OK] .gitignore contains .scriptorium entry"

proc testSkipsExistingAgentsMd() =
  ## Verify runInit preserves existing AGENTS.md with custom content.
  let repo = createTempRepo()
  defer: removeDir(repo)

  let customContent = "# Custom AGENTS.md\nDo not overwrite me.\n"
  let agentsPath = repo / "AGENTS.md"
  writeFile(agentsPath, customContent)
  let qpath = quoteShell(repo)
  discard execCmdEx("git -C " & qpath & " add AGENTS.md")
  discard execCmdEx("git -C " & qpath & " commit -m \"add custom AGENTS.md\"")

  runInit(repo, quiet = true)

  let afterContent = readFile(agentsPath)
  doAssert afterContent == customContent, "AGENTS.md should preserve custom content"
  echo "[OK] runInit skips existing AGENTS.md"

proc testSkipsExistingMakefile() =
  ## Verify runInit preserves existing Makefile with custom content.
  let repo = createTempRepo()
  defer: removeDir(repo)

  let customContent = "all:\n\t@echo custom\n"
  let makefilePath = repo / "Makefile"
  writeFile(makefilePath, customContent)
  let qpath = quoteShell(repo)
  discard execCmdEx("git -C " & qpath & " add Makefile")
  discard execCmdEx("git -C " & qpath & " commit -m \"add custom Makefile\"")

  runInit(repo, quiet = true)

  let afterContent = readFile(makefilePath)
  doAssert afterContent == customContent, "Makefile should preserve custom content"
  echo "[OK] runInit skips existing Makefile"

proc testTestConfigNimsCreated() =
  ## Verify runInit creates tests/config.nims with the src path directive.
  let repo = createTempRepo()
  defer: removeDir(repo)

  runInit(repo, quiet = true)

  let configNimsPath = repo / "tests" / "config.nims"
  doAssert fileExists(configNimsPath), "tests/config.nims should exist after init"
  let content = readFile(configNimsPath)
  doAssert "--path:\"../src\"" in content, "tests/config.nims should contain --path:\"../src\""
  echo "[OK] runInit creates tests/config.nims with path directive"

when isMainModule:
  testNotAGitRepo()
  testAlreadyInitializedFails()
  testSuccessfulInit()
  testSpecPlaceholderContent()
  testDoubleInitFails()
  testInitNoRemote()
  testMakefileContainsAllTargets()
  testSrcAndDocsCreated()
  testAgentsMdCreated()
  testConfigJsonCreated()
  testGitignoreEntry()
  testSkipsExistingAgentsMd()
  testSkipsExistingMakefile()
  testTestConfigNimsCreated()
