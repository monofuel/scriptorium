## Shared test helpers for scriptorium test suites.

import
  std/[algorithm, json, os, osproc, sequtils, strformat, strutils, tables, tempfiles, unittest],
  jsony,
  scriptorium/[agent_runner, config, init, orchestrator, ticket_metadata]

export os, osproc, sequtils, strformat, strutils, tables, tempfiles, unittest
export json, jsony
export agent_runner, config, init, orchestrator, ticket_metadata

const
  OrchestratorTestBasePort* = 19000

type
  StreamMessageJson* = object
    `type`*: string
    text*: string

proc makeTestRepo*(path: string) =
  ## Create a minimal git repository at path suitable for testing.
  if dirExists(path):
    removeDir(path)
  createDir(path)
  discard execCmdEx("git -C " & path & " init")
  discard execCmdEx("git -C " & path & " config user.email test@test.com")
  discard execCmdEx("git -C " & path & " config user.name Test")
  discard execCmdEx("git -C " & path & " commit --allow-empty -m initial")

proc runCmdOrDie*(cmd: string) =
  ## Run a shell command and fail the test immediately if it exits non-zero.
  let (_, rc) = execCmdEx(cmd)
  doAssert rc == 0, cmd

proc normalizedPathForTest*(path: string): string =
  ## Return an absolute path with forward slash separators for assertions.
  result = absolutePath(path).replace('\\', '/')

proc writeScriptoriumConfig*(repoPath: string, cfg: Config) =
  ## Write one typed scriptorium.json payload for test configuration.
  writeFile(repoPath / "scriptorium.json", cfg.toJson())

proc writeOrchestratorEndpointConfig*(repoPath: string, portOffset: int, maxAttempts: int = 2) =
  ## Write a unique local orchestrator endpoint configuration for one test.
  let basePort = OrchestratorTestBasePort + (getCurrentProcessId().int mod 1000)
  let orchestratorPort = basePort + portOffset
  var cfg = defaultConfig()
  cfg.endpoints.local = &"http://127.0.0.1:{orchestratorPort}"
  cfg.timeouts.codingAgentMaxAttempts = maxAttempts
  writeScriptoriumConfig(repoPath, cfg)

proc withPlanWorktree*(repoPath: string, suffix: string, action: proc(planPath: string)) =
  ## Open scriptorium/plan in a temporary worktree for direct test mutations.
  let tmpPlan = getTempDir() / ("scriptorium_test_plan_" & suffix & "_" & $getCurrentProcessId())
  if dirExists(tmpPlan):
    removeDir(tmpPlan)

  runCmdOrDie("git -C " & quoteShell(repoPath) & " worktree add " & quoteShell(tmpPlan) & " scriptorium/plan")
  defer:
    discard execCmdEx("git -C " & quoteShell(repoPath) & " worktree remove --force " & quoteShell(tmpPlan))

  action(tmpPlan)

proc removeSpecFromPlan*(repoPath: string) =
  ## Remove spec.md from scriptorium/plan and commit the change.
  withPlanWorktree(repoPath, "remove_spec", proc(planPath: string) =
    runCmdOrDie("git -C " & quoteShell(planPath) & " rm spec.md")
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-remove-spec")
  )

proc addAreaToPlan*(repoPath: string, fileName: string, content: string) =
  ## Add one area markdown file to scriptorium/plan and commit the change.
  withPlanWorktree(repoPath, "add_area", proc(planPath: string) =
    let relPath = "areas/" & fileName
    writeFile(planPath / relPath, content)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add " & quoteShell(relPath))
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-add-area")
  )

proc writeSpecInPlan*(repoPath: string, content: string) =
  ## Replace spec.md on scriptorium/plan and commit the change.
  withPlanWorktree(repoPath, "write_spec", proc(planPath: string) =
    writeFile(planPath / "spec.md", content)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add spec.md")
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-write-spec")
  )

proc addTicketToPlan*(repoPath: string, state: string, fileName: string, content: string) =
  ## Add one ticket file to a plan ticket state directory and commit it.
  withPlanWorktree(repoPath, "add_ticket", proc(planPath: string) =
    let relPath = "tickets" / state / fileName
    writeFile(planPath / relPath, content)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add " & quoteShell(relPath))
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-add-ticket")
  )

proc moveTicketStateInPlan*(repoPath: string, fromState: string, toState: string, fileName: string) =
  ## Move a ticket file from one state directory to another and commit.
  withPlanWorktree(repoPath, "move_ticket_state", proc(planPath: string) =
    let fromPath = "tickets" / fromState / fileName
    let toPath = "tickets" / toState / fileName
    moveFile(planPath / fromPath, planPath / toPath)
    runCmdOrDie("git -C " & quoteShell(planPath) & " add -A " & quoteShell("tickets"))
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-move-ticket")
  )

proc writeSpecHashInPlan*(repoPath: string, hash: string) =
  ## Write areas/.spec-hash on scriptorium/plan and commit.
  withPlanWorktree(repoPath, "write_spec_hash", proc(planPath: string) =
    createDir(planPath / "areas")
    writeFile(planPath / "areas/.spec-hash", hash & "\n")
    runCmdOrDie("git -C " & quoteShell(planPath) & " add areas/.spec-hash")
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-write-spec-hash")
  )

proc writeAreaHashesInPlan*(repoPath: string, hashes: Table[string, string]) =
  ## Write tickets/.area-hashes on scriptorium/plan and commit.
  withPlanWorktree(repoPath, "write_area_hashes", proc(planPath: string) =
    createDir(planPath / "tickets")
    var lines: seq[string] = @[]
    for areaId, hash in hashes:
      lines.add(areaId & ":" & hash)
    lines.sort()
    writeFile(planPath / "tickets/.area-hashes", lines.join("\n") & "\n")
    runCmdOrDie("git -C " & quoteShell(planPath) & " add tickets/.area-hashes")
    runCmdOrDie("git -C " & quoteShell(planPath) & " commit -m test-write-area-hashes")
  )

proc planCommitCount*(repoPath: string): int =
  ## Return the commit count reachable from the plan branch.
  let (output, rc) = execCmdEx("git -C " & quoteShell(repoPath) & " rev-list --count scriptorium/plan")
  doAssert rc == 0
  result = parseInt(output.strip())

proc planTreeFiles*(repoPath: string): seq[string] =
  ## Return file paths from the plan branch tree.
  let (output, rc) = execCmdEx("git -C " & quoteShell(repoPath) & " ls-tree -r --name-only scriptorium/plan")
  doAssert rc == 0
  result = output.splitLines().filterIt(it.len > 0)

proc gitWorktreePaths*(repoPath: string): seq[string] =
  ## Return absolute paths from git worktree list.
  let (output, rc) = execCmdEx("git -C " & quoteShell(repoPath) & " worktree list --porcelain")
  doAssert rc == 0
  for line in output.splitLines():
    if line.startsWith("worktree "):
      result.add(line["worktree ".len..^1].strip())

proc addPassingMakefile*(repoPath: string) =
  ## Add a Makefile with passing quality-gate targets and commit it on master.
  writeFile(
    repoPath / "Makefile",
    "test:\n\t@echo PASS test\n\nintegration-test:\n\t@echo PASS integration-test\n",
  )
  runCmdOrDie("git -C " & quoteShell(repoPath) & " add Makefile")
  runCmdOrDie("git -C " & quoteShell(repoPath) & " commit -m test-add-passing-makefile")

proc addFailingMakefile*(repoPath: string) =
  ## Add a Makefile where `make test` fails and `make integration-test` is defined.
  writeFile(
    repoPath / "Makefile",
    "test:\n\t@echo FAIL test\n\t@false\n\nintegration-test:\n\t@echo PASS integration-test\n",
  )
  runCmdOrDie("git -C " & quoteShell(repoPath) & " add Makefile")
  runCmdOrDie("git -C " & quoteShell(repoPath) & " commit -m test-add-failing-makefile")

proc addIntegrationFailingMakefile*(repoPath: string) =
  ## Add a Makefile where `make test` passes and `make integration-test` fails.
  writeFile(
    repoPath / "Makefile",
    "test:\n\t@echo PASS test\n\nintegration-test:\n\t@echo FAIL integration-test\n\t@false\n",
  )
  runCmdOrDie("git -C " & quoteShell(repoPath) & " add Makefile")
  runCmdOrDie("git -C " & quoteShell(repoPath) & " commit -m test-add-integration-failing-makefile")

proc withTempRepo*(prefix: string, action: proc(repoPath: string)) =
  ## Create a temporary git repository, run action, and clean up afterwards.
  let repoPath = createTempDir(prefix, "", getTempDir())
  defer:
    removeDir(repoPath)
  makeTestRepo(repoPath)
  action(repoPath)

proc pendingQueueFiles*(repoPath: string): seq[string] =
  ## Return pending merge-queue markdown entries sorted by file name.
  let files = planTreeFiles(repoPath)
  result = files.filterIt(it.startsWith("queue/merge/pending/") and it.endsWith(".md"))
  result.sort()

proc readPlanFile*(repoPath: string, relPath: string): string =
  ## Read one file from the plan branch tree.
  let (output, rc) = execCmdEx(
    "git -C " & quoteShell(repoPath) & " show scriptorium/plan:" & relPath
  )
  doAssert rc == 0, relPath
  result = output

proc latestPlanCommits*(repoPath: string, count: int): seq[string] =
  ## Return the latest commit subjects from the plan branch.
  let (output, rc) = execCmdEx(
    "git -C " & quoteShell(repoPath) & " log --format=%s -n " & $count & " scriptorium/plan"
  )
  doAssert rc == 0
  result = output.splitLines().filterIt(it.len > 0)

proc callSubmitPrTool*(summary: string) =
  ## Simulate one coding-agent submit_pr MCP tool call.
  discard consumeSubmitPrSummary()
  let httpServer = createOrchestratorServer()
  doAssert httpServer.server.toolHandlers.hasKey("submit_pr")
  let submitPrHandler = httpServer.server.toolHandlers["submit_pr"]
  discard submitPrHandler(%*{"summary": summary})

proc noopRunner*(request: AgentRunRequest): AgentRunResult =
  ## Fake agent runner that returns immediately with no review decision.
  ## When used with processMergeQueue the review agent stalls and defaults to approve.
  discard request
  AgentRunResult(exitCode: 0, backend: harnessCodex, timeoutKind: "none")
