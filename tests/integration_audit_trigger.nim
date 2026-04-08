## Integration tests for needsAudit — requires a real git repo with plan branch.

import
  std/[os, osproc, unittest],
  scriptorium/[audit_agent, git_ops]

proc makeTestRepo(path: string) =
  ## Create a minimal git repository at path.
  if dirExists(path):
    removeDir(path)
  createDir(path)
  discard execCmdEx("git -C " & path & " init")
  discard execCmdEx("git -C " & path & " config user.email test@test.com")
  discard execCmdEx("git -C " & path & " config user.name Test")
  writeFile(path / "README.md", "initial")
  discard execCmdEx("git -C " & path & " add README.md")
  discard execCmdEx("git -C " & path & " commit -m initial")

proc makeTestRepoWithPlanBranch(path: string) =
  ## Create a test repo with a plan branch containing required directories.
  makeTestRepo(path)
  discard execCmdEx("git -C " & path & " checkout -b scriptorium/plan")
  createDir(path / "tickets" / "open")
  createDir(path / "tickets" / "in-progress")
  createDir(path / "tickets" / "done")
  createDir(path / "queue" / "merge" / "pending")
  writeFile(path / "tickets" / "open" / ".gitkeep", "")
  writeFile(path / "tickets" / "in-progress" / ".gitkeep", "")
  writeFile(path / "tickets" / "done" / ".gitkeep", "")
  writeFile(path / "queue" / "merge" / "pending" / ".gitkeep", "")
  writeFile(path / "queue" / "merge" / "active.md", "")
  discard execCmdEx("git -C " & path & " add -A")
  discard execCmdEx("git -C " & path & " commit -m 'init plan branch'")
  discard execCmdEx("git -C " & path & " checkout master")

proc runCmdOrDie(cmd: string) =
  ## Run a shell command and fail the test immediately if it exits non-zero.
  let (output, rc) = execCmdEx(cmd)
  doAssert rc == 0, cmd & ": " & output

suite "needsAudit integration":
  test "returns true when no audit state exists":
    let tmpDir = getTempDir() / "audit_needs_none_" & $getCurrentProcessId()
    makeTestRepoWithPlanBranch(tmpDir)
    defer: removeDir(tmpDir)
    check needsAudit(tmpDir) == true

  test "returns false when HEAD matches last audited commit":
    let tmpDir = getTempDir() / "audit_needs_match_" & $getCurrentProcessId()
    makeTestRepoWithPlanBranch(tmpDir)
    defer: removeDir(tmpDir)
    let headCommit = defaultBranchHeadCommit(tmpDir)
    # Write audit state with current HEAD on the plan branch.
    runCmdOrDie("git -C " & tmpDir & " checkout scriptorium/plan")
    writeFile(tmpDir / AuditStatePath, "{\"lastAuditedCommit\":\"" & headCommit & "\"}")
    runCmdOrDie("git -C " & tmpDir & " add " & AuditStatePath)
    runCmdOrDie("git -C " & tmpDir & " commit -m 'set audit state'")
    runCmdOrDie("git -C " & tmpDir & " checkout master")
    check needsAudit(tmpDir) == false

  test "returns true when HEAD differs from last audited commit":
    let tmpDir = getTempDir() / "audit_needs_diff_" & $getCurrentProcessId()
    makeTestRepoWithPlanBranch(tmpDir)
    defer: removeDir(tmpDir)
    # Write audit state with an old commit on the plan branch.
    runCmdOrDie("git -C " & tmpDir & " checkout scriptorium/plan")
    writeFile(tmpDir / AuditStatePath, "{\"lastAuditedCommit\":\"0000000000000000000000000000000000000000\"}")
    runCmdOrDie("git -C " & tmpDir & " add " & AuditStatePath)
    runCmdOrDie("git -C " & tmpDir & " commit -m 'set old audit state'")
    runCmdOrDie("git -C " & tmpDir & " checkout master")
    check needsAudit(tmpDir) == true
