import std/[os, osproc, streams, strformat, strutils]

const
  PlanBranch = "scriptorium/plan"
  SpecPlaceholder = "# Spec\n\nRun `scriptorium plan` to build your spec with the Architect.\n"
  AgentsFileName = "AGENTS.md"
  AgentsTemplate = staticRead("prompts/agents_example.md")
  PlanDirs = [
    "areas",
    "tickets/open",
    "tickets/in-progress",
    "tickets/done",
    "tickets/stuck",
    "decisions",
  ]

proc gitRun(dir: string, args: varargs[string]) =
  ## Run a git subcommand in dir, raising IOError on non-zero exit.
  let argsSeq = @args
  let allArgs = @["-C", dir] & argsSeq
  let p = startProcess("git", args = allArgs, options = {poUsePath, poStdErrToStdOut})
  let output = p.outputStream.readAll()
  let rc = p.waitForExit()
  p.close()
  if rc != 0:
    let argsStr = argsSeq.join(" ")
    raise newException(IOError, fmt"git {argsStr} failed: {output.strip()}")

proc gitCheck(dir: string, args: varargs[string]): int =
  ## Run a git subcommand in dir, returning exit code and discarding output.
  let allArgs = @["-C", dir] & @args
  let p = startProcess("git", args = allArgs, options = {poUsePath, poStdErrToStdOut})
  discard p.outputStream.readAll()
  result = p.waitForExit()
  p.close()

proc resolveDefaultBranch(repoPath: string): string =
  ## Dynamically detect the default branch for the repository.
  ## Checks refs/remotes/origin/HEAD first, then probes for master, main, develop.
  let symrefProcess = startProcess(
    "git",
    args = @["-C", repoPath, "symbolic-ref", "refs/remotes/origin/HEAD"],
    options = {poUsePath, poStdErrToStdOut},
  )
  let symrefOutput = symrefProcess.outputStream.readAll()
  let symrefRc = symrefProcess.waitForExit()
  symrefProcess.close()
  if symrefRc == 0:
    let symref = symrefOutput.strip()
    let prefix = "refs/remotes/origin/"
    if symref.startsWith(prefix):
      result = symref[prefix.len..^1]
      return

  const ProbeBranches = ["master", "main", "develop"]
  for branch in ProbeBranches:
    if gitCheck(repoPath, "rev-parse", "--verify", branch) == 0:
      result = branch
      return

  raise newException(IOError, "cannot determine default branch: refs/remotes/origin/HEAD is not set and none of master, main, develop exist")

proc runInit*(path: string, quiet: bool = false) =
  ## Initialize a new scriptorium workspace in the given git repository.
  let target = if path.len > 0: absolutePath(path) else: getCurrentDir()

  if gitCheck(target, "rev-parse", "--git-dir") != 0:
    raise newException(ValueError, fmt"{target} is not a git repository")

  if gitCheck(target, "rev-parse", "--verify", PlanBranch) == 0:
    raise newException(ValueError, "workspace already initialized (scriptorium/plan branch exists)")

  let defaultBranch = resolveDefaultBranch(target)
  discard execCmdEx("git -C " & quoteShell(target) & " remote set-head origin " & quoteShell(defaultBranch))

  let agentsPath = target / AgentsFileName
  let createdAgents = not fileExists(agentsPath)
  if createdAgents:
    writeFile(agentsPath, AgentsTemplate)
    gitRun(target, "add", AgentsFileName)
    gitRun(target, "commit", "-m", "scriptorium: add AGENTS.md from template")

  let tmpPlan = getTempDir() / "scriptorium_plan_init"
  if dirExists(tmpPlan):
    removeDir(tmpPlan)

  gitRun(target, "worktree", "add", "--orphan", "-b", PlanBranch, tmpPlan)
  defer:
    discard execCmdEx(
      "git -C " & quoteShell(target) & " worktree remove --force " & quoteShell(tmpPlan)
    )

  for d in PlanDirs:
    createDir(tmpPlan / d)
    writeFile(tmpPlan / d / ".gitkeep", "")
  writeFile(tmpPlan / "spec.md", SpecPlaceholder)

  gitRun(tmpPlan, "add", ".")
  gitRun(tmpPlan, "commit", "-m", "scriptorium: initialize plan branch")

  if not quiet:
    echo "Initialized scriptorium workspace."
    echo &"  Plan branch: {PlanBranch}"
    if createdAgents:
      echo &"  Created: {AgentsFileName}"
    echo ""
    echo "Next steps:"
    echo "  scriptorium plan   — build your spec with the Architect"
    echo "  scriptorium run    — start the orchestrator"
