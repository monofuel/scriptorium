## Tests for the scriptorium CLI and core utilities.

import std/[os, osproc, sequtils, strutils, unittest]
import scriptorium/[init, config, orchestrator]

proc makeTestRepo(path: string) =
  ## Create a minimal git repository at path suitable for testing.
  createDir(path)
  discard execCmdEx("git -C " & path & " init")
  discard execCmdEx("git -C " & path & " config user.email test@test.com")
  discard execCmdEx("git -C " & path & " config user.name Test")
  discard execCmdEx("git -C " & path & " commit --allow-empty -m initial")

proc runCmdOrDie(cmd: string) =
  ## Run a shell command and fail the test immediately if it exits non-zero.
  let (_, rc) = execCmdEx(cmd)
  doAssert rc == 0, cmd

proc withPlanWorktree(repoPath: string, suffix: string, action: proc(planPath: string)) =
  ## Open scriptorium/plan in a temporary worktree for direct test mutations.
  let tmpPlan = getTempDir() / ("scriptorium_test_plan_" & suffix)
  if dirExists(tmpPlan):
    removeDir(tmpPlan)

  runCmdOrDie("git -C " & quoteShell(repoPath) & " worktree add " & quoteShell(tmpPlan) & " scriptorium/plan")
  defer:
    discard execCmdEx("git -C " & quoteShell(repoPath) & " worktree remove --force " & quoteShell(tmpPlan))

  action(tmpPlan)

proc removeSpecFromPlan(repoPath: string) =
  ## Remove spec.md from scriptorium/plan and commit the change.
  withPlanWorktree(repoPath, "remove_spec", proc(planPath: string) =
    runCmdOrDie("git -C " & quoteShell(planPath) & " rm spec.md")
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-remove-spec")
  )

proc addAreaToPlan(repoPath: string, fileName: string, content: string) =
  ## Add one area markdown file to scriptorium/plan and commit the change.
  withPlanWorktree(repoPath, "add_area", proc(planPath: string) =
    let relPath = "areas/" & fileName
    writeFile(planPath / relPath, content)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add " & quoteShell(relPath))
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-add-area")
  )

proc addTicketToPlan(repoPath: string, state: string, fileName: string, content: string) =
  ## Add one ticket file to a plan ticket state directory and commit it.
  withPlanWorktree(repoPath, "add_ticket", proc(planPath: string) =
    let relPath = "tickets" / state / fileName
    writeFile(planPath / relPath, content)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add " & quoteShell(relPath))
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-add-ticket")
  )

proc planCommitCount(repoPath: string): int =
  ## Return the commit count reachable from the plan branch.
  let (output, rc) = execCmdEx("git -C " & quoteShell(repoPath) & " rev-list --count scriptorium/plan")
  doAssert rc == 0
  result = parseInt(output.strip())

proc planTreeFiles(repoPath: string): seq[string] =
  ## Return file paths from the plan branch tree.
  let (output, rc) = execCmdEx("git -C " & quoteShell(repoPath) & " ls-tree -r --name-only scriptorium/plan")
  doAssert rc == 0
  result = output.splitLines().filterIt(it.len > 0)

suite "scriptorium --init":
  test "creates scriptorium/plan branch":
    let tmp = getTempDir() / "scriptorium_test_init_branch"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    runInit(tmp)

    let (_, rc) = execCmdEx("git -C " & tmp & " rev-parse --verify scriptorium/plan")
    check rc == 0

  test "plan branch contains correct folder structure":
    let tmp = getTempDir() / "scriptorium_test_init_structure"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    runInit(tmp)

    let (files, _) = execCmdEx("git -C " & tmp & " ls-tree -r --name-only scriptorium/plan")
    check "spec.md" in files
    check "areas/.gitkeep" in files
    check "tickets/open/.gitkeep" in files
    check "tickets/in-progress/.gitkeep" in files
    check "tickets/done/.gitkeep" in files
    check "decisions/.gitkeep" in files

  test "raises on already initialized workspace":
    let tmp = getTempDir() / "scriptorium_test_init_dupe"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    runInit(tmp)
    expect ValueError:
      runInit(tmp)

  test "raises on non-git directory":
    let tmp = getTempDir() / "scriptorium_test_not_a_repo"
    createDir(tmp)
    defer: removeDir(tmp)

    expect ValueError:
      runInit(tmp)

suite "config":
  test "defaults to codex-mini for both roles":
    let cfg = defaultConfig()
    check cfg.models.architect == "codex-mini"
    check cfg.models.coding == "codex-mini"

  test "loads from scriptorium.json":
    let tmp = getTempDir() / "scriptorium_test_config"
    createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "scriptorium.json", """{"models":{"architect":"claude-opus-4-6","coding":"grok-code-fast-1"},"endpoints":{"local":"http://localhost:1234/v1"}}""")

    let cfg = loadConfig(tmp)
    check cfg.models.architect == "claude-opus-4-6"
    check cfg.models.coding == "grok-code-fast-1"
    check cfg.endpoints.local == "http://localhost:1234/v1"

  test "missing file returns defaults":
    let tmp = getTempDir() / "scriptorium_test_config_missing"
    createDir(tmp)
    defer: removeDir(tmp)

    let cfg = loadConfig(tmp)
    check cfg.models.architect == "codex-mini"
    check cfg.models.coding == "codex-mini"

  test "harness routing":
    check harness("claude-opus-4-6") == harnessClaudeCode
    check harness("claude-haiku-4-5") == harnessClaudeCode
    check harness("codex-mini") == harnessCodex
    check harness("gpt-4o") == harnessCodex
    check harness("grok-code-fast-1") == harnessTypoi
    check harness("local/qwen3.5-35b-a3b") == harnessTypoi

suite "orchestrator endpoint":
  test "empty endpoint falls back to default":
    let endpoint = parseEndpoint("")
    check endpoint.address == "127.0.0.1"
    check endpoint.port == 8097

  test "parses endpoint from config value":
    let tmp = getTempDir() / "scriptorium_test_orchestrator_endpoint"
    createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "scriptorium.json", """{"endpoints":{"local":"http://localhost:1234/v1"}}""")

    let endpoint = loadOrchestratorEndpoint(tmp)
    check endpoint.address == "localhost"
    check endpoint.port == 1234

  test "rejects endpoint missing host":
    expect ValueError:
      discard parseEndpoint("http:///v1")

suite "orchestrator planning bootstrap":
  test "loads spec from plan branch":
    let tmp = getTempDir() / "scriptorium_test_plan_load_spec"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp)

    let spec = loadSpecFromPlan(tmp)
    check "Run `scriptorium plan`" in spec

  test "missing spec raises error":
    let tmp = getTempDir() / "scriptorium_test_plan_missing_spec"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp)
    removeSpecFromPlan(tmp)

    expect ValueError:
      discard loadSpecFromPlan(tmp)

  test "areas missing is true for blank plan and false when area exists":
    let tmp = getTempDir() / "scriptorium_test_areas_missing"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp)

    check areasMissing(tmp)
    addAreaToPlan(tmp, "01-cli.md", "# Area 01\n")
    check not areasMissing(tmp)

  test "sync areas calls architect with configured model and spec":
    let tmp = getTempDir() / "scriptorium_test_sync_areas_call"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp)
    writeFile(tmp / "scriptorium.json", """{"models":{"architect":"claude-opus-4-6"}}""")

    var callCount = 0
    var capturedModel = ""
    var capturedSpec = ""
    proc generator(model: string, spec: string): seq[AreaDocument] =
      ## Capture architect invocation arguments and return one area.
      inc callCount
      capturedModel = model
      capturedSpec = spec
      result = @[
        AreaDocument(path: "01-cli.md", content: "# Area 01\n\n## Scope\n- CLI\n")
      ]

    let synced = syncAreasFromSpec(tmp, generator)
    check synced
    check callCount == 1
    check capturedModel == "claude-opus-4-6"
    check "Run `scriptorium plan`" in capturedSpec

    let (files, rc) = execCmdEx("git -C " & quoteShell(tmp) & " ls-tree -r --name-only scriptorium/plan")
    check rc == 0
    check "areas/01-cli.md" in files

  test "sync areas is idempotent on second run":
    let tmp = getTempDir() / "scriptorium_test_sync_areas_idempotent"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp)

    var callCount = 0
    proc generator(model: string, spec: string): seq[AreaDocument] =
      ## Return stable area output for idempotence checks.
      inc callCount
      discard model
      discard spec
      result = @[
        AreaDocument(path: "01-cli.md", content: "# Area 01\n\n## Scope\n- CLI\n")
      ]

    let before = planCommitCount(tmp)
    let firstSync = syncAreasFromSpec(tmp, generator)
    let afterFirst = planCommitCount(tmp)
    let secondSync = syncAreasFromSpec(tmp, generator)
    let afterSecond = planCommitCount(tmp)

    check firstSync
    check not secondSync
    check callCount == 1
    check afterFirst == before + 1
    check afterSecond == afterFirst

suite "orchestrator manager ticket bootstrap":
  test "areas needing tickets excludes areas with open or in-progress work":
    let tmp = getTempDir() / "scriptorium_test_areas_needing_tickets"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp)
    addAreaToPlan(tmp, "01-cli.md", "# Area 01\n")
    addAreaToPlan(tmp, "02-core.md", "# Area 02\n")
    addTicketToPlan(tmp, "open", "0001-cli-ticket.md", "# Ticket\n\n**Area:** 01-cli\n")

    let needed = areasNeedingTickets(tmp)
    check "areas/02-core.md" in needed
    check "areas/01-cli.md" notin needed

  test "sync tickets calls manager with configured coding model":
    let tmp = getTempDir() / "scriptorium_test_sync_tickets_call"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp)
    addAreaToPlan(tmp, "01-cli.md", "# Area 01\n\n## Scope\n- CLI\n")
    writeFile(tmp / "scriptorium.json", """{"models":{"coding":"grok-code-fast-1"}}""")

    var callCount = 0
    var capturedModel = ""
    var capturedAreaPath = ""
    var capturedAreaContent = ""
    proc generator(model: string, areaPath: string, areaContent: string): seq[TicketDocument] =
      ## Capture manager invocation arguments and return one ticket.
      inc callCount
      capturedModel = model
      capturedAreaPath = areaPath
      capturedAreaContent = areaContent
      result = @[
        TicketDocument(slug: "cli-bootstrap", content: "# Ticket 1\n")
      ]

    let before = planCommitCount(tmp)
    let synced = syncTicketsFromAreas(tmp, generator)
    let after = planCommitCount(tmp)

    check synced
    check callCount == 1
    check capturedModel == "grok-code-fast-1"
    check capturedAreaPath == "areas/01-cli.md"
    check "## Scope" in capturedAreaContent
    check after == before + 1

    let files = planTreeFiles(tmp)
    check "tickets/open/0001-cli-bootstrap.md" in files

    let (logOutput, rc) = execCmdEx(
      "git -C " & quoteShell(tmp) & " log --oneline -1 scriptorium/plan"
    )
    check rc == 0
    check "scriptorium: create tickets from areas" in logOutput

  test "ticket IDs are monotonic based on existing highest ID":
    let tmp = getTempDir() / "scriptorium_test_ticket_id_monotonic"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp)
    addAreaToPlan(tmp, "01-cli.md", "# Area 01\n")
    addAreaToPlan(tmp, "02-core.md", "# Area 02\n")
    addTicketToPlan(tmp, "done", "0042-already-done.md", "# Done Ticket\n\n**Area:** old\n")

    proc generator(model: string, areaPath: string, areaContent: string): seq[TicketDocument] =
      ## Return one ticket per area for monotonic ID checks.
      discard model
      discard areaPath
      discard areaContent
      result = @[
        TicketDocument(slug: "next-task", content: "# New Ticket\n")
      ]

    discard syncTicketsFromAreas(tmp, generator)

    let files = planTreeFiles(tmp)
    check "tickets/open/0043-next-task.md" in files
    check "tickets/open/0044-next-task.md" in files

  test "sync tickets is idempotent on second run":
    let tmp = getTempDir() / "scriptorium_test_sync_tickets_idempotent"
    makeTestRepo(tmp)
    defer: removeDir(tmp)
    runInit(tmp)
    addAreaToPlan(tmp, "01-cli.md", "# Area 01\n")

    var callCount = 0
    proc generator(model: string, areaPath: string, areaContent: string): seq[TicketDocument] =
      ## Return stable ticket output for idempotence checks.
      inc callCount
      discard model
      discard areaPath
      discard areaContent
      result = @[
        TicketDocument(slug: "stable-task", content: "# Stable Ticket\n")
      ]

    let before = planCommitCount(tmp)
    let firstSync = syncTicketsFromAreas(tmp, generator)
    let afterFirst = planCommitCount(tmp)
    let secondSync = syncTicketsFromAreas(tmp, generator)
    let afterSecond = planCommitCount(tmp)

    check firstSync
    check not secondSync
    check callCount == 1
    check afterFirst == before + 1
    check afterSecond == afterFirst
