import
  std/[os, osproc, strutils],
  scriptorium/init

const
  SpecPlaceholder = "# Spec\n\nRun `scriptorium plan` to build your spec with the Architect.\n"
  ExpectedDirs = [
    "areas",
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

when isMainModule:
  testNotAGitRepo()
  testAlreadyInitializedFails()
  testSuccessfulInit()
  testSpecPlaceholderContent()
  testDoubleInitFails()
  testInitNoRemote()
  testMakefileContainsAllTargets()
  testSrcAndDocsCreated()
