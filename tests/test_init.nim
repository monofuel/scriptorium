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

proc testAlreadyInitializedDoesNotCrash() =
  ## Verify runInit succeeds when scriptorium/plan branch already exists.
  let repo = createTempRepo()
  defer: removeDir(repo)

  let qpath = quoteShell(repo)
  discard execCmdEx("git -C " & qpath & " branch scriptorium/plan")

  # Should not raise. Idempotent.
  runInit(repo, quiet = true)
  echo "[OK] runInit does not crash when plan branch already exists"

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

proc testDoubleInitIdempotent() =
  ## Verify running init twice does not crash and preserves all state.
  let repo = createTempRepo()
  defer: removeDir(repo)

  runInit(repo, quiet = true)

  let qpath = quoteShell(repo)
  let (sha1, _) = execCmdEx("git -C " & qpath & " rev-parse scriptorium/plan")

  # Second init should succeed without error.
  runInit(repo, quiet = true)

  # Plan branch should still exist with same commit.
  let (sha2, rc2) = execCmdEx("git -C " & qpath & " rev-parse scriptorium/plan")
  doAssert rc2 == 0, "scriptorium/plan branch should still exist"
  doAssert sha1.strip() == sha2.strip(), "plan branch commit should be unchanged"

  # Files created by first init should still be present.
  doAssert fileExists(repo / "AGENTS.md")
  doAssert fileExists(repo / "Makefile")
  doAssert fileExists(repo / "tests" / "config.nims")
  doAssert fileExists(repo / "scriptorium.json")
  echo "[OK] double init is idempotent"

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

when isMainModule:
  testNotAGitRepo()
  testAlreadyInitializedDoesNotCrash()
  testSuccessfulInit()
  testSpecPlaceholderContent()
  testDoubleInitIdempotent()
  testInitNoRemote()
