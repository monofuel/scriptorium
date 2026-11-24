import
  std/[json, os, osproc, strutils, tempfiles, unittest],
  acport,
  scriptorium/[agent_runner, mcp_server, orchestrator],
  helpers

proc checkReviewGate(scenario: string, approval: string = "") =
  ## Exercise the merge queue with a controlled reviewer and observable Git gates.
  let repo = createTempDir("scriptorium-review-gate-", "")
  defer: removeDir(repo)
  makeInitializedTestRepo(repo)
  writeFile(repo / "Makefile", "test integration-test:\n\t@touch quality-ran\n")
  gitRun(repo, "add", "Makefile")
  gitRun(repo, "commit", "-m", "quality gate fixture")
  addTicketToPlan(repo, "open", "0001-review.md", "# Review gate\n\n**Area:** a\n")
  let assignment = assignOldestOpenTicket(repo)
  writeFile(assignment.worktree / "reviewed.txt", "ticket change\n")
  gitRun(assignment.worktree, "add", "reviewed.txt")
  gitRun(assignment.worktree, "commit", "-m", "ticket change")
  discard enqueueMergeRequest(repo, assignment, "review gate regression")
  let
    branch = resolveDefaultBranch(repo)
    before = gitRunCapture(repo, @["rev-parse", branch]).output
    other = newReviewerMcpSession("http://127.0.0.1:19097", "other-ticket")
    stale = newReviewerMcpSession("http://127.0.0.1:19097", "0001")
  defer: unregisterAgentMcpSession(other)
  discard invokeAgentMcpTool(stale.endpoint, "submit_review", %*{"action": "approve"})
  unregisterAgentMcpSession(stale)
  var currentEndpoint = ""
  proc reviewer(request: AgentRunRequest): AgentRunResult =
    ## Submit scoped verdicts and simulate failures without launching providers.
    currentEndpoint = request.mcpEndpoint
    result = AgentRunResult(exitCode: 0, timeoutKind: "none")
    case scenario
    of "missing":
      result.lastMessage = "approve"
      result.stdout = "approve_with_warnings"
    of "error", "approved-error":
      result.exitCode = 1
      result.failureKind = failureRpc
      result.errorMessage = "reviewer RPC failed"
    of "timeout", "approved-timeout":
      result.exitCode = 1
      result.failureKind = failureTimeout
      result.timeoutKind = "hard"
    of "typed-failure": result.failureKind = failureTransport
    of "timeout-marker": result.timeoutKind = "no_output"
    of "cancelled": result.cancelled = true
    of "refused": result.stopReason = refused
    of "exception": raise newException(IOError, "reviewer transport raised")
    of "invalid":
      discard invokeAgentMcpTool(request.mcpEndpoint, "submit_review", %*{"action": "approved"})
    of "cross-session":
      discard invokeAgentMcpTool(other.endpoint, "submit_review", %*{"action": "approve"})
    of "stale-session":
      expect ValueError:
        discard invokeAgentMcpTool(stale.endpoint, "submit_review", %*{"action": "approve"})
    of "changes":
      discard invokeAgentMcpTool(request.mcpEndpoint, "submit_review",
        %*{"action": "request_changes", "feedback": "Fix this first."})
      discard invokeAgentMcpTool(request.mcpEndpoint, "submit_review", %*{"action": "approve"})
    of "explicit": discard
    else: raise newException(ValueError, "Unknown review fixture: " & scenario)
    if approval.len > 0:
      discard invokeAgentMcpTool(request.mcpEndpoint, "submit_review",
        %*{"action": approval, "feedback": "Warning retained."})

  if scenario == "exception":
    expect IOError:
      discard processMergeQueue(repo, reviewer)
  else:
    check processMergeQueue(repo, reviewer)
  let
    after = gitRunCapture(repo, @["rev-parse", branch]).output
    files = planTreeFiles(repo)
    shouldMerge = scenario == "explicit"
  check fileExists(assignment.worktree / "quality-ran") == shouldMerge
  check fileExists(repo / "reviewed.txt") == shouldMerge
  check (after != before) == shouldMerge
  check ("tickets/done/0001-review.md" in files) == shouldMerge
  check ("tickets/open/0001-review.md" in files) == (not shouldMerge and scenario != "exception")
  check ("tickets/in-progress/0001-review.md" in files) == (scenario == "exception")
  let content = readPlanFile(repo,
    if shouldMerge: "tickets/done/0001-review.md"
    elif scenario == "exception": "tickets/in-progress/0001-review.md"
    else: "tickets/open/0001-review.md")
  if shouldMerge:
    check "**Review:** approved" in content
    if approval == "approve_with_warnings":
      check "**Warnings:** Warning retained." in content
  else:
    if scenario != "exception": check "**Review:** changes requested" in content
    check "**Review:** approved" notin content
    if scenario == "changes": check "Fix this first." in content
  expect ValueError:
    discard invokeAgentMcpTool(currentEndpoint, "submit_review", %*{"action": "approve"})

suite "review approval is required before quality gates and default branch merge":
  for scenario in ["missing", "error", "timeout", "exception", "invalid", "cross-session", "stale-session", "changes"]:
    test scenario:
      checkReviewGate(scenario)
  for scenario in ["approved-error", "approved-timeout", "typed-failure", "timeout-marker", "cancelled", "refused"]:
    for action in ["approve", "approve_with_warnings"]:
      test scenario & " after " & action:
        checkReviewGate(scenario, action)
  for action in ["approve", "approve_with_warnings"]:
    test "successful explicit " & action:
      checkReviewGate("explicit", action)
