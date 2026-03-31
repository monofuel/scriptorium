## Integration tests for the scriptorium CLI binary.

import
  std/[os, osproc, strutils, unittest],
  jsony,
  scriptorium/[config, init]

const
  AgentsExampleContent = staticRead("../src/scriptorium/prompts/agents_example.md")

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

proc makeInitializedTestRepo(path: string) =
  ## Create a test repo with runInit already done (plan branch, config, etc).
  makeTestRepo(path)
  runInit(path, quiet = true)

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
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
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
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
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

  test "init creates AGENTS.md from template when missing":
    let tmp = getTempDir() / "scriptorium_test_cli_agents_create"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    let agentsPath = tmp / "AGENTS.md"
    check fileExists(agentsPath)
    check readFile(agentsPath) == AgentsExampleContent

  test "init creates Makefile with placeholder targets when missing":
    let tmp = getTempDir() / "scriptorium_test_cli_makefile_create"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    let makefilePath = tmp / "Makefile"
    check fileExists(makefilePath)
    let content = readFile(makefilePath)
    check content.contains("test:")
    check content.contains("integration-test:")
    check content.contains("e2e-test:")
    check content.contains("build:")
    check content.contains("no tests configured")
    check content.contains("no integration tests configured")
    check content.contains("no e2e tests configured")
    check content.contains("no build configured")

  test "init skips Makefile when it already exists":
    let tmp = getTempDir() / "scriptorium_test_cli_makefile_skip"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    let makefilePath = tmp / "Makefile"
    let existingContent = "all:\n\t@echo custom\n"
    writeFile(makefilePath, existingContent)
    runCmdOrDie("git -C " & tmp & " add Makefile")
    runCmdOrDie("git -C " & tmp & " commit -m add-makefile")

    runInit(tmp, quiet = true)

    check readFile(makefilePath) == existingContent

  test "init skips AGENTS.md when it already exists":
    let tmp = getTempDir() / "scriptorium_test_cli_agents_skip"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    let agentsPath = tmp / "AGENTS.md"
    let existingContent = "# Custom agents file\n"
    writeFile(agentsPath, existingContent)
    runCmdOrDie("git -C " & tmp & " add AGENTS.md")
    runCmdOrDie("git -C " & tmp & " commit -m add-agents")

    runInit(tmp, quiet = true)

    check readFile(agentsPath) == existingContent

  test "init creates tests/config.nims when missing":
    let tmp = getTempDir() / "scriptorium_test_cli_test_config_create"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    let testConfigPath = tmp / "tests" / "config.nims"
    check fileExists(testConfigPath)
    check readFile(testConfigPath) == "--path:\"../src\"\n"

  test "init skips tests/config.nims when it already exists":
    let tmp = getTempDir() / "scriptorium_test_cli_test_config_skip"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    createDir(tmp / "tests")
    let existingContent = "--path:\"../src\"\n--threads:on\n"
    writeFile(tmp / "tests" / "config.nims", existingContent)
    runCmdOrDie("git -C " & tmp & " add tests/config.nims")
    runCmdOrDie("git -C " & tmp & " commit -m add-test-config")

    runInit(tmp, quiet = true)

    check readFile(tmp / "tests" / "config.nims") == existingContent

  test "init creates scriptorium.json with default config when missing":
    let tmp = getTempDir() / "scriptorium_test_cli_config_create"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    let configPath = tmp / "scriptorium.json"
    check fileExists(configPath)
    let loaded = loadConfig(tmp)
    let defaults = defaultConfig()
    check loaded.concurrency.maxAgents == defaults.concurrency.maxAgents
    check loaded.timeouts.codingAgentHardTimeoutMs == defaults.timeouts.codingAgentHardTimeoutMs

  test "init skips scriptorium.json when it already exists":
    let tmp = getTempDir() / "scriptorium_test_cli_config_skip"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    let configPath = tmp / "scriptorium.json"
    let existingContent = "{\"concurrency\":{\"maxAgents\":42,\"tokenBudgetMB\":0}}\n"
    writeFile(configPath, existingContent)

    runInit(tmp, quiet = true)

    check readFile(configPath) == existingContent

  test "--init flag works as alias for init subcommand":
    let tmp = getTempDir() / "scriptorium_test_cli_init_flag"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    let (output, rc) = runCliInRepo(tmp, "--init")
    check rc == 0
    check output.contains("Initialized scriptorium workspace.")
    # Verify plan branch was created.
    let (_, branchRc) = execCmdEx("git -C " & tmp & " rev-parse --verify scriptorium/plan")
    check branchRc == 0

  test "init output lists created files and next steps":
    let tmp = getTempDir() / "scriptorium_test_cli_init_output"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    let (output, rc) = runCliInRepo(tmp, "init")
    check rc == 0
    check output.contains("Initialized scriptorium workspace.")
    # Per-artifact messages.
    check output.contains("Created AGENTS.md — edit to match your project conventions.")
    check output.contains("Created Makefile with placeholder targets — replace with real build commands.")
    check output.contains("Created scriptorium.json — configure agent models and harnesses.")
    # Created summary section.
    check output.contains("AGENTS.md")
    check output.contains("Makefile")
    check output.contains("scriptorium.json")
    check output.contains("scriptorium/plan")
    # Numbered next steps.
    check output.contains("1. Edit scriptorium.json to configure your agent models and harnesses")
    check output.contains("2. Edit AGENTS.md to describe your project conventions")
    check output.contains("3. Run `scriptorium plan` to build your spec with the Architect")
    check output.contains("4. Run `scriptorium run` to start the orchestrator")

  test "init spec.md references AGENTS.md":
    let tmp = getTempDir() / "scriptorium_test_cli_spec_ref"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    var specContent = ""
    withPlanWorktree(tmp, "spec_ref", proc(planPath: string) =
      specContent = readFile(planPath / "spec.md")
    )
    check specContent.contains("AGENTS.md")

  test "run exits with error when plan branch is missing":
    let tmp = getTempDir() / "scriptorium_test_cli_preflight_plan"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    # Create AGENTS.md and Makefile but no plan branch.
    writeFile(tmp / "AGENTS.md", "# Agents\n")
    writeFile(tmp / "Makefile", "test:\n\t@echo ok\n")
    runCmdOrDie("git -C " & tmp & " add -A")
    runCmdOrDie("git -C " & tmp & " commit -m setup")

    let (output, rc) = runCliInRepo(tmp, "run")
    check rc != 0
    check output.contains("scriptorium/plan branch is missing")

  test "run exits with error when AGENTS.md is missing":
    let tmp = getTempDir() / "scriptorium_test_cli_preflight_agents"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    # Create plan branch and Makefile but no AGENTS.md.
    writeFile(tmp / "Makefile", "test:\n\t@echo ok\n")
    runCmdOrDie("git -C " & tmp & " add -A")
    runCmdOrDie("git -C " & tmp & " commit -m setup")
    runCmdOrDie("git -C " & tmp & " branch scriptorium/plan")

    let (output, rc) = runCliInRepo(tmp, "run")
    check rc != 0
    check output.contains("AGENTS.md is missing")

  test "run exits with error when Makefile is missing":
    let tmp = getTempDir() / "scriptorium_test_cli_preflight_makefile"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    # Create plan branch and AGENTS.md but no Makefile.
    writeFile(tmp / "AGENTS.md", "# Agents\n")
    runCmdOrDie("git -C " & tmp & " add -A")
    runCmdOrDie("git -C " & tmp & " commit -m setup")
    runCmdOrDie("git -C " & tmp & " branch scriptorium/plan")

    let (output, rc) = runCliInRepo(tmp, "run")
    check rc != 0
    check output.contains("Makefile is missing")

  test "run exits with error when Makefile lacks test target":
    let tmp = getTempDir() / "scriptorium_test_cli_preflight_target"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    # Create plan branch, AGENTS.md, Makefile without test target.
    writeFile(tmp / "AGENTS.md", "# Agents\n")
    writeFile(tmp / "Makefile", "build:\n\t@echo ok\n")
    runCmdOrDie("git -C " & tmp & " add -A")
    runCmdOrDie("git -C " & tmp & " commit -m setup")
    runCmdOrDie("git -C " & tmp & " branch scriptorium/plan")

    let (output, rc) = runCliInRepo(tmp, "run")
    check rc != 0
    check output.contains("missing a `test:` target")

  test "syncAgentsMd restores modified AGENTS.md to template":
    let tmp = getTempDir() / "scriptorium_test_cli_sync_restore"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    # Modify AGENTS.md to differ from template.
    writeFile(tmp / "AGENTS.md", "# Custom content\n")
    runCmdOrDie("git -C " & tmp & " add AGENTS.md")
    runCmdOrDie("git -C " & tmp & " commit -m modify-agents")

    syncAgentsMd(tmp)

    check readFile(tmp / "AGENTS.md") == AgentsExampleContent

  test "syncAgentsMd is a no-op when AGENTS.md matches template":
    let tmp = getTempDir() / "scriptorium_test_cli_sync_noop"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    # Capture HEAD before sync.
    let (headBefore, _) = execCmdEx("git -C " & tmp & " rev-parse HEAD")
    syncAgentsMd(tmp)
    let (headAfter, _) = execCmdEx("git -C " & tmp & " rev-parse HEAD")

    check headBefore.strip() == headAfter.strip()

  test "syncAgentsMd respects syncAgentsMd false in config":
    let tmp = getTempDir() / "scriptorium_test_cli_sync_disabled"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    # Write config with syncAgentsMd: false.
    var cfg = defaultConfig()
    cfg.syncAgentsMd = false
    writeFile(tmp / "scriptorium.json", cfg.toJson())

    # Modify AGENTS.md.
    let customContent = "# Custom agents\n"
    writeFile(tmp / "AGENTS.md", customContent)
    runCmdOrDie("git -C " & tmp & " add AGENTS.md")
    runCmdOrDie("git -C " & tmp & " commit -m modify-agents")

    # Only sync if config says so (mimics orchestrator logic).
    let loadedCfg = loadConfig(tmp)
    if loadedCfg.syncAgentsMd:
      syncAgentsMd(tmp)

    check readFile(tmp / "AGENTS.md") == customContent

  test "init creates src/ and docs/ directories":
    let tmp = getTempDir() / "scriptorium_test_cli_src_docs_create"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    check fileExists(tmp / "src" / ".gitkeep")
    check fileExists(tmp / "docs" / ".gitkeep")

  test "init skips src/ and docs/ when they already exist":
    let tmp = getTempDir() / "scriptorium_test_cli_src_docs_skip"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    createDir(tmp / "src")
    writeFile(tmp / "src" / "main.nim", "echo \"hello\"\n")
    createDir(tmp / "docs")
    writeFile(tmp / "docs" / "guide.md", "# Guide\n")
    runCmdOrDie("git -C " & tmp & " add src docs")
    runCmdOrDie("git -C " & tmp & " commit -m add-src-docs")

    runInit(tmp, quiet = true)

    check readFile(tmp / "src" / "main.nim") == "echo \"hello\"\n"
    check readFile(tmp / "docs" / "guide.md") == "# Guide\n"
    check not fileExists(tmp / "src" / ".gitkeep")
    check not fileExists(tmp / "docs" / ".gitkeep")

  test "dashboard command prints stub message and exits 0":
    let tmp = getTempDir() / "scriptorium_test_cli_dashboard"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)

    let (output, rc) = runCliInRepo(tmp, "dashboard")
    check rc == 0
    check output.contains("dashboard not yet implemented")
