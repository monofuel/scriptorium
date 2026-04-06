import std/[os, osproc, streams, strformat, strutils]
import jsony
from ./git_ops import ensureScriptoriumIgnored
from ./config import defaultConfig

const
  PlanBranch = "scriptorium/plan"
  SpecPlaceholder = "# Spec\n\nThis is a new project. See AGENTS.md for project conventions.\n\nRun `scriptorium plan` to build your spec with the Architect.\n"
  AgentsFileName = "AGENTS.md"
  AgentsTemplate = staticRead("prompts/agents_example.md")
  MakefileName = "Makefile"
  MakefileTemplate = ".PHONY: test integration-test e2e-test build\n\ntest:\n\t@echo \"no tests configured\"\n\nintegration-test:\n\t@echo \"no integration tests configured\"\n\ne2e-test:\n\t@echo \"no e2e tests configured\"\n\nbuild:\n\t@echo \"no build configured\"\n"
  TestConfigNimsName = "tests" / "config.nims"
  TestConfigNimsContent = "--path:\"../src\"\n"
  ConfigFileName = "scriptorium.json"
  PlanDirs = [
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

proc syncAgentsMd*(repoPath: string) =
  ## Overwrite AGENTS.md with the built-in template if it differs.
  ## Commits the change when an update is made.
  let agentsPath = repoPath / AgentsFileName
  if not fileExists(agentsPath):
    writeFile(agentsPath, AgentsTemplate)
    gitRun(repoPath, "add", AgentsFileName)
    gitRun(repoPath, "commit", "-m", "scriptorium: sync AGENTS.md from template")
    return
  let current = readFile(agentsPath)
  if current != AgentsTemplate:
    writeFile(agentsPath, AgentsTemplate)
    gitRun(repoPath, "add", AgentsFileName)
    gitRun(repoPath, "commit", "-m", "scriptorium: sync AGENTS.md from template")

proc hasOriginRemote(repoPath: string): bool =
  ## Return true when the repository has an origin remote configured.
  result = gitCheck(repoPath, "remote", "get-url", "origin") == 0

proc runInit*(path: string, quiet: bool = false) =
  ## Initialize a new scriptorium workspace in the given git repository.
  ## Raises ValueError if the plan branch already exists.
  let target = if path.len > 0: absolutePath(path) else: getCurrentDir()

  if gitCheck(target, "rev-parse", "--git-dir") != 0:
    raise newException(ValueError, &"{target} is not a git repository")

  let planBranchExists = gitCheck(target, "rev-parse", "--verify", PlanBranch) == 0
  if planBranchExists:
    raise newException(ValueError, "scriptorium/plan branch already exists — workspace is already initialized")

  # Detect default branch. Fall back to "master" if detection fails (no remote, unusual naming).
  var defaultBranch = "master"
  try:
    defaultBranch = resolveDefaultBranch(target)
  except IOError:
    if not quiet:
      echo "scriptorium: could not detect default branch, using 'master'"

  # Set remote HEAD if origin exists.
  if hasOriginRemote(target):
    discard execCmdEx("git -C " & quoteShell(target) & " remote set-head origin " & quoteShell(defaultBranch))

  ensureScriptoriumIgnored(target)

  let agentsPath = target / AgentsFileName
  let createdAgents = not fileExists(agentsPath)
  if createdAgents:
    writeFile(agentsPath, AgentsTemplate)
    gitRun(target, "add", AgentsFileName)
    gitRun(target, "commit", "-m", "scriptorium: add AGENTS.md from template")
    if not quiet:
      echo "Created AGENTS.md — edit to match your project conventions."

  let makefilePath = target / MakefileName
  let createdMakefile = not fileExists(makefilePath)
  if createdMakefile:
    writeFile(makefilePath, MakefileTemplate)
    gitRun(target, "add", MakefileName)
    gitRun(target, "commit", "-m", "scriptorium: add starter Makefile")
    if not quiet:
      echo "Created Makefile with placeholder targets — replace with real build commands."

  let testConfigPath = target / TestConfigNimsName
  let createdTestConfig = not fileExists(testConfigPath)
  if createdTestConfig:
    createDir(target / "tests")
    writeFile(testConfigPath, TestConfigNimsContent)
    gitRun(target, "add", TestConfigNimsName)
    gitRun(target, "commit", "-m", "scriptorium: add tests/config.nims")

  let srcKeep = "src" / ".gitkeep"
  let createdSrc = not dirExists(target / "src")
  if createdSrc:
    createDir(target / "src")
    writeFile(target / srcKeep, "")
    gitRun(target, "add", srcKeep)
    gitRun(target, "commit", "-m", "scriptorium: add src/ directory")

  let docsKeep = "docs" / ".gitkeep"
  let createdDocs = not dirExists(target / "docs")
  if createdDocs:
    createDir(target / "docs")
    writeFile(target / docsKeep, "")
    gitRun(target, "add", docsKeep)
    gitRun(target, "commit", "-m", "scriptorium: add docs/ directory")

  let configPath = target / ConfigFileName
  let createdConfig = not fileExists(configPath)
  if createdConfig:
    let configJson = defaultConfig().toJson()
    writeFile(configPath, configJson & "\n")
    if not quiet:
      echo "Created scriptorium.json — configure agent models and harnesses."

  # Create plan branch.
  let tmpPlan = target / ".scriptorium" / "plan_init"

  # Clean up stale worktree from a previous interrupted init.
  discard gitCheck(target, "worktree", "remove", "--force", tmpPlan)
  discard gitCheck(target, "worktree", "prune")
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
    echo ""
    echo "Initialized scriptorium workspace."
    echo ""
    echo "Created:"
    if createdAgents:
      echo "  AGENTS.md           — project conventions for coding agents (edit to fit)"
    if createdMakefile:
      echo "  Makefile            — placeholder test targets (replace with real commands)"
    if createdConfig:
      echo "  scriptorium.json    — agent configuration (set your models and API keys)"
    echo &"  {PlanBranch}    — plan branch with spec, areas, and tickets"
    if createdTestConfig:
      echo "  tests/config.nims   — test path configuration"
    if createdSrc:
      echo "  src/                — source directory"
    if createdDocs:
      echo "  docs/               — documentation directory"
    echo ""
    echo "Next steps:"
    var stepNum = 1
    if createdConfig:
      echo &"  {stepNum}. Edit scriptorium.json to configure your agent models and harnesses"
      stepNum += 1
    if createdAgents:
      echo &"  {stepNum}. Edit AGENTS.md to describe your project conventions"
      stepNum += 1
    echo &"  {stepNum}. Run `scriptorium plan` to build your spec with the Architect"
    stepNum += 1
    echo &"  {stepNum}. Run `scriptorium run` to start the orchestrator"
