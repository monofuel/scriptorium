## Integration tests for the scriptorium CLI binary.

import
  std/[os, osproc, unittest],
  scriptorium/init

const
  CliBinaryName = "scriptorium_test_cli"
let
  ProjectRoot = getCurrentDir()
var
  cliBinaryPath = ""

proc makeTestRepo(path: string) =
  ## Create a minimal git repository at path suitable for testing.
  if dirExists(path):
    removeDir(path)
  createDir(path)
  discard execCmdEx("git -C " & path & " init")
  discard execCmdEx("git -C " & path & " config user.email test@test.com")
  discard execCmdEx("git -C " & path & " config user.name Test")
  discard execCmdEx("git -C " & path & " commit --allow-empty -m initial")

proc runCmdOrDie(cmd: string) =
  ## Run a shell command and fail the test immediately if it exits non-zero.
  let (_, rc) = execCmdEx(cmd)
  doAssert rc == 0, cmd

proc ensureCliBinary(): string =
  ## Build and cache the scriptorium CLI binary for command-output tests.
  if cliBinaryPath.len == 0:
    cliBinaryPath = getTempDir() / CliBinaryName
    runCmdOrDie(
      "nim c -o:" & quoteShell(cliBinaryPath) & " " & quoteShell(ProjectRoot / "src/scriptorium.nim")
    )
  result = cliBinaryPath

proc runCliInRepo(repoPath: string, args: string): tuple[output: string, exitCode: int] =
  ## Run the compiled CLI in repoPath and return output and exit code.
  let command = "cd " & quoteShell(repoPath) & " && " & quoteShell(ensureCliBinary()) & " " & args
  result = execCmdEx(command)

proc withPlanWorktree(repoPath: string, suffix: string, action: proc(planPath: string)) =
  ## Open scriptorium/plan in a temporary worktree for direct test mutations.
  let tmpPlan = getTempDir() / ("scriptorium_test_plan_" & suffix)
  if dirExists(tmpPlan):
    removeDir(tmpPlan)

  runCmdOrDie("git -C " & quoteShell(repoPath) & " worktree add " & quoteShell(tmpPlan) & " scriptorium/plan")
  defer:
    discard execCmdEx("git -C " & quoteShell(repoPath) & " worktree remove --force " & quoteShell(tmpPlan))

  action(tmpPlan)

proc addTicketToPlan(repoPath: string, state: string, fileName: string, content: string) =
  ## Add one ticket file to a plan ticket state directory and commit it.
  withPlanWorktree(repoPath, "add_ticket", proc(planPath: string) =
    let relPath = "tickets" / state / fileName
    writeFile(planPath / relPath, content)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add " & quoteShell(relPath))
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-add-ticket")
  )

suite "scriptorium CLI":
  test "status command prints ticket counts and active agent snapshot":
    let tmp = getTempDir() / "scriptorium_test_cli_status"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(tmp, "open", "0001-first.md", "# Ticket 1\n\n**Area:** a\n")
    addTicketToPlan(
      tmp,
      "in-progress",
      "0002-second.md",
      "# Ticket 2\n\n**Area:** b\n\n**Worktree:** /tmp/worktree-0002\n",
    )

    let (output, rc) = runCliInRepo(tmp, "status")
    let expected =
      "Open: 1\n" &
      "In Progress: 1\n" &
      "Done: 0\n" &
      "Active Agent Ticket: 0002 (tickets/in-progress/0002-second.md)\n" &
      "Active Agent Branch: scriptorium/ticket-0002\n" &
      "Active Agent Worktree: /tmp/worktree-0002\n"

    check rc == 0
    check output == expected

  test "worktrees command lists active ticket worktrees":
    let tmp = getTempDir() / "scriptorium_test_cli_worktrees"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp, quiet = true)
    addTicketToPlan(
      tmp,
      "in-progress",
      "0002-second.md",
      "# Ticket 2\n\n**Area:** b\n\n**Worktree:** /tmp/worktree-0002\n",
    )
    addTicketToPlan(
      tmp,
      "in-progress",
      "0001-first.md",
      "# Ticket 1\n\n**Area:** a\n\n**Worktree:** /tmp/worktree-0001\n",
    )

    let (output, rc) = runCliInRepo(tmp, "worktrees")
    let expected =
      "WORKTREE\tTICKET\tBRANCH\n" &
      "/tmp/worktree-0001\t0001\tscriptorium/ticket-0001\n" &
      "/tmp/worktree-0002\t0002\tscriptorium/ticket-0002\n"

    check rc == 0
    check output == expected
