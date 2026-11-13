## Unit tests for agent-scoped MCP servers and completion state.

import
  std/[json, os, strutils, tables, tempfiles, unittest],
  scriptorium/mcp_server

const
  TestEndpoint = "http://127.0.0.1:19097"

suite "agent-scoped MCP tool catalogs":
  setup:
    let directory = createTempDir("scriptorium-mcp-unit-", "")
  teardown:
    removeDir(directory)
  test "coding server requires a completion summary":
    let session = newCodingMcpSession(TestEndpoint, "0001", "ticket-0001", (directory / "wt-0001"))
    defer: unregisterAgentMcpSession(session)

    check session.server.tools.len == 1
    check session.server.tools.hasKey("submit_pr")
    let schema = session.server.tools["submit_pr"].inputSchema
    check schema["required"][0].getStr() == "summary"
    check schema["properties"].hasKey("summary")
    check not schema["properties"].hasKey("ticket_id")
    check schema["additionalProperties"].getBool() == false

  test "manager server exposes only submit_tickets without area identity":
    let session = newManagerMcpSession(TestEndpoint, "backend")
    defer: unregisterAgentMcpSession(session)

    check session.server.tools.len == 1
    check session.server.tools.hasKey("submit_tickets")
    let schema = session.server.tools["submit_tickets"].inputSchema
    check schema["required"][0].getStr() == "tickets"
    check not schema["properties"].hasKey("area_id")

  test "reviewer and audit servers expose only their own tools":
    let reviewer = newReviewerMcpSession(TestEndpoint, "0002")
    let audit = newAuditMcpSession(TestEndpoint)
    defer:
      unregisterAgentMcpSession(reviewer)
      unregisterAgentMcpSession(audit)

    check reviewer.server.tools.len == 1
    check reviewer.server.tools.hasKey("submit_review")
    check audit.server.tools.len == 1
    check audit.server.tools.hasKey("submit_audit_report")

suite "agent-scoped MCP completion":
  setup:
    let directory = createTempDir("scriptorium-mcp-unit-", "")
  teardown:
    removeDir(directory)
  test "submit_pr rejects missing summaries and binds the assigned ticket":
    let session = newCodingMcpSession(TestEndpoint, "0022", "ticket-0022", (directory / "wt-0022"))
    defer: unregisterAgentMcpSession(session)

    expect ValueError:
      discard invokeAgentMcpTool(session.endpoint, "submit_pr", %*{})
    let submission = codingSubmission(session)
    check not submission.called
    check submission.summary == ""
    check session.ticketId == "0022"
    check session.worktree == (directory / "wt-0022")

  test "parallel coding sessions cannot cross completion state":
    let first = newCodingMcpSession(TestEndpoint, "0030", "ticket-0030", (directory / "wt-0030"))
    let second = newCodingMcpSession(TestEndpoint, "0031", "ticket-0031", (directory / "wt-0031"))
    defer:
      unregisterAgentMcpSession(first)
      unregisterAgentMcpSession(second)

    discard invokeAgentMcpTool(first.endpoint, "submit_pr", %*{"summary": "first"})
    check codingSubmission(first) == (called: true, summary: "first")
    check codingSubmission(second) == (called: false, summary: "")

    discard invokeAgentMcpTool(second.endpoint, "submit_pr", %*{"summary": "second"})
    check codingSubmission(first).summary == "first"
    check codingSubmission(second).summary == "second"

  test "duplicate completion calls do not overwrite the first result":
    let session = newCodingMcpSession(TestEndpoint, "0040", "ticket-0040", (directory / "wt-0040"))
    defer: unregisterAgentMcpSession(session)

    discard invokeAgentMcpTool(session.endpoint, "submit_pr", %*{"summary": "first"})
    discard invokeAgentMcpTool(session.endpoint, "submit_pr", %*{"summary": "second"})
    check codingSubmission(session).summary == "first"

  test "durable completion survives registration and is consumed after enqueue":
    let worktree = directory / "receipt"
    let first = newCodingMcpSession(TestEndpoint, "receipt", "branch", worktree)
    discard invokeAgentMcpTool(first.endpoint, "submit_pr", %*{"summary": "durable"})
    unregisterAgentMcpSession(first)
    let restored = newCodingMcpSession(TestEndpoint, "receipt", "branch", worktree)
    check restored.endpoint != first.endpoint
    check codingSubmission(restored) == (called: true, summary: "durable")
    acknowledgeCodingSubmission(restored)
    unregisterAgentMcpSession(restored)
    let consumed = newCodingMcpSession(TestEndpoint, "receipt", "branch", worktree)
    defer: unregisterAgentMcpSession(consumed)
    check not codingSubmission(consumed).called

  test "manager session binds area and captures only ticket content":
    let session = newManagerMcpSession(TestEndpoint, "frontend")
    defer: unregisterAgentMcpSession(session)

    discard invokeAgentMcpTool(session.endpoint, "submit_tickets", %*{
      "tickets": ["# First", "# Second"],
    })
    let submission = managerSubmission(session)
    check submission.called
    check submission.tickets == @["# First", "# Second"]
    check session.areaId == "frontend"

  test "review feedback is validated and bounded per session":
    let session = newReviewerMcpSession(TestEndpoint, "0050")
    defer: unregisterAgentMcpSession(session)

    let missing = invokeAgentMcpTool(session.endpoint, "submit_review", %*{
      "action": "request_changes",
    })
    check "Feedback is required" in missing.getStr()
    check not reviewerSubmission(session).called

    let oversized = 'x'.repeat(ReviewFeedbackMaxBytes + 1)
    discard invokeAgentMcpTool(session.endpoint, "submit_review", %*{
      "action": "request_changes",
      "feedback": oversized,
    })
    let submission = reviewerSubmission(session)
    check submission.called
    check submission.feedback.len == ReviewFeedbackMaxBytes
    check submission.feedback.endsWith(ReviewTruncationMarker)

  test "audit report stays in its own session":
    let first = newAuditMcpSession(TestEndpoint)
    let second = newAuditMcpSession(TestEndpoint)
    defer:
      unregisterAgentMcpSession(first)
      unregisterAgentMcpSession(second)

    discard invokeAgentMcpTool(first.endpoint, "submit_audit_report", %*{"report": "report one"})
    check auditSubmission(first).report == "report one"
    check not auditSubmission(second).called

  test "unregistered endpoint expires":
    let session = newCodingMcpSession(TestEndpoint, "0060", "ticket-0060", (directory / "wt-0060"))
    unregisterAgentMcpSession(session)

    expect ValueError:
      discard invokeAgentMcpTool(session.endpoint, "submit_pr", %*{})
