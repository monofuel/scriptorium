import
  std/[os, strutils, tempfiles, unittest],
  scriptorium/[interactive_sessions],
  helpers

proc turn(repo: string, runner: AgentRunner, ask = false): ArchitectTurnResult =
  ## Run a synthetic turn under the same admin and plan locks as the ACP owner.
  acquireAdminLock(repo)
  defer: releaseAdminLock(repo)
  withLockedPlanWorktree(repo, proc(plan: string): ArchitectTurnResult =
    ## Exercise actual Git finalization with a deterministic native runner.
    let architect = loadConfig(repo).agents.architect
    if ask:
      runArchitectAskTurn(runner, repo, plan, architect, @[], "synthetic question", "synthetic", nil)
    else:
      runArchitectPlanTurn(runner, repo, plan, architect, @[], "synthetic plan", 1, "synthetic", nil))

proc completed(): AgentRunResult =
  ## Represent a real successful native end-turn with a final answer.
  AgentRunResult(exitCode: 0, failureKind: failureNone, lastMessage: "Plan complete.",
    transcriptText: "Plan complete.", stopReasonReceived: true)

suite "Plan spec commit finalization":
  setup:
    let repo = createTempDir("scriptorium-plan-finalization-", "")
    makeInitializedTestRepo(repo)
    let before = gitRunCapture(repo, @["rev-parse", "scriptorium/plan"]).output.strip()
    let mainBefore = gitRunCapture(repo, @["rev-parse", "HEAD"]).output.strip()
  teardown:
    check gitRunCapture(repo, @["rev-parse", "HEAD"]).output.strip() == mainBefore
    check not fileExists(repo / ".scriptorium" / "admin.lock")
    removeDir(repo)

  test "already committed native spec succeeds without a duplicate wrapper commit":
    var nativeHead = ""
    let runner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      ## Commit only the synthetic spec as the native Architect did in the reported failure.
      check request.allowedWritePaths == @["spec.md"]
      writeFile(request.workingDir / "spec.md", "# Native committed spec\n")
      gitRun(request.workingDir, "add", "spec.md")
      gitRun(request.workingDir, "commit", "-m", "synthetic native spec")
      nativeHead = gitRunCapture(request.workingDir, @["rev-parse", "HEAD"]).output.strip()
      completed()
    let result = turn(repo, runner)
    check result.agentResult.failureKind == failureNone
    check result.response == "Plan complete."
    check result.specChanged
    check gitRunCapture(repo, @["rev-parse", "scriptorium/plan"]).output.strip() == nativeHead
    check gitRunCapture(repo, @["rev-list", "--count", before & "..scriptorium/plan"]).output.strip() == "1"

  test "dirty spec is committed once and a direct ticket write is reverted":
    let runner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      ## Write a spec and attempt to bypass the downstream manager.
      writeFile(request.workingDir / "spec.md", "# Wrapper committed spec\n")
      writeFile(request.workingDir / "tickets/open/1234-direct.md", "# Forbidden direct ticket\n")
      completed()
    let result = turn(repo, runner)
    check result.agentResult.failureKind == failureNone
    check result.specChanged
    check gitRunCapture(repo, @["rev-list", "--count", before & "..scriptorium/plan"]).output.strip() == "1"
    check gitCheck(repo, "cat-file", "-e", "scriptorium/plan:tickets/open/1234-direct.md") != 0

  test "no-change answer does not advance the plan":
    let runner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      ## Answer without changing planning state.
      completed()
    let result = turn(repo, runner)
    check result.agentResult.failureKind == failureNone
    check not result.specChanged
    check gitRunCapture(repo, @["rev-parse", "scriptorium/plan"]).output.strip() == before

  test "Ask reverts attempted writes and never commits":
    let runner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      ## Attempt a write despite the read-only question contract.
      check request.accessPolicy == accessReadOnly
      writeFile(request.workingDir / "spec.md", "# Disallowed Ask write\n")
      completed()
    let result = turn(repo, runner, ask = true)
    check result.agentResult.failureKind == failureNone
    check gitRunCapture(repo, @["rev-parse", "scriptorium/plan"]).output.strip() == before

  test "native error and cancellation remain failures without wrapper commits":
    for failure in [failureRpc, failureCancelled]:
      let runner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
        ## Return an actual native failure classification with no successful final answer.
        AgentRunResult(exitCode: 1, failureKind: failure, errorMessage: "synthetic native failure")
      let result = turn(repo, runner)
      check result.agentResult.failureKind == failure
      check result.response.len == 0
      check gitRunCapture(repo, @["rev-parse", "scriptorium/plan"]).output.strip() == before

  test "native commits outside spec are rejected without rewriting their history":
    var nativeHead = ""
    let runner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      ## Preserve a deliberately invalid native commit for explicit inspection.
      writeFile(request.workingDir / "outside.md", "Synthetic invalid native change.\n")
      gitRun(request.workingDir, "add", "outside.md")
      gitRun(request.workingDir, "commit", "-m", "synthetic invalid native commit")
      nativeHead = gitRunCapture(request.workingDir, @["rev-parse", "HEAD"]).output.strip()
      completed()
    let result = turn(repo, runner)
    check result.agentResult.failureKind == failureProtocol
    check "disallowed path" in result.agentResult.errorMessage
    check gitRunCapture(repo, @["rev-parse", "scriptorium/plan"]).output.strip() == nativeHead
