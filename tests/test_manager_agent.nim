## Unit tests for per-area manager agent: prompt building and submit_tickets MCP state.

import
  std/[os, strutils, unittest],
  scriptorium/[agent_runner, manager_agent, prompt_builders, prompt_catalog, shared_state, ticket_metadata]

suite "buildManagerTicketsPrompt":
  test "renders single-area prompt with all placeholders":
    let prompt = buildManagerTicketsPrompt(
      repoPath = "/repo",
      areaId = "backend-api",
      areaRelPath = "areas/backend-api.md",
      areaContent = "Build the REST API endpoints.",
      nextId = 42,
    )
    check prompt.contains("/repo")
    check prompt.contains("backend-api")
    check prompt.contains("areas/backend-api.md")
    check prompt.contains("Build the REST API endpoints.")
    check prompt.contains("0042")
    check prompt.contains(AreaFieldPrefix)

  test "prompt contains no unresolved placeholders":
    let prompt = buildManagerTicketsPrompt(
      repoPath = "/repo",
      areaId = "frontend",
      areaRelPath = "areas/frontend.md",
      areaContent = "UI components.",
      nextId = 1,
    )
    check not prompt.contains("{{")
    check not prompt.contains("}}")

  test "nextId is zero-padded to four digits":
    let prompt = buildManagerTicketsPrompt(
      repoPath = "/r",
      areaId = "a",
      areaRelPath = "areas/a.md",
      areaContent = "content",
      nextId = 7,
    )
    check prompt.contains("0007")

suite "submit_tickets MCP state":
  test "recordSubmitTickets and consumeSubmitTickets round-trip":
    let tickets = @["# Ticket 1\n\nContent.", "# Ticket 2\n\nMore content."]
    recordSubmitTickets("backend", tickets)
    let consumed = consumeSubmitTickets("backend")
    check consumed.len == 2
    check consumed[0].contains("# Ticket 1")
    check consumed[1].contains("# Ticket 2")

  test "consumeSubmitTickets returns empty when no tickets recorded":
    let consumed = consumeSubmitTickets("nonexistent")
    check consumed.len == 0

  test "consumeSubmitTickets clears state after consumption":
    recordSubmitTickets("frontend", @["# T1\n\nContent."])
    discard consumeSubmitTickets("frontend")
    let second = consumeSubmitTickets("frontend")
    check second.len == 0

suite "writeTicketsForAreaFromStrings":
  test "writes ticket files with area field and sequential IDs":
    let tmpDir = getTempDir() / "test_write_tickets_from_strings"
    let ticketsDir = tmpDir / "tickets" / "open"
    createDir(ticketsDir)
    defer: removeDir(tmpDir)

    let docs = @[
      "# Add Login\n\nImplement login page.",
      "# Add Signup\n\nImplement signup page.",
    ]
    writeTicketsForAreaFromStrings(tmpDir, "frontend", docs, 10)

    let ticket1 = readFile(ticketsDir / "0010-add-login.md")
    check ticket1.contains("# Add Login")
    check ticket1.contains(AreaFieldPrefix & " frontend")

    let ticket2 = readFile(ticketsDir / "0011-add-signup.md")
    check ticket2.contains("# Add Signup")
    check ticket2.contains(AreaFieldPrefix & " frontend")

  test "preserves existing area field when it matches":
    let tmpDir = getTempDir() / "test_write_tickets_area_match"
    let ticketsDir = tmpDir / "tickets" / "open"
    createDir(ticketsDir)
    defer: removeDir(tmpDir)

    let docs = @["# My Ticket\n\nSome content.\n\n**Area:** backend"]
    writeTicketsForAreaFromStrings(tmpDir, "backend", docs, 1)

    let content = readFile(ticketsDir / "0001-my-ticket.md")
    check content.contains("# My Ticket")
    check content.contains("**Area:** backend")
    # Should not have duplicate area field.
    check content.count("**Area:**") == 1

  test "raises on area mismatch":
    let tmpDir = getTempDir() / "test_write_tickets_area_mismatch"
    let ticketsDir = tmpDir / "tickets" / "open"
    createDir(ticketsDir)
    defer: removeDir(tmpDir)

    let docs = @["# My Ticket\n\nContent.\n\n**Area:** wrong-area"]
    expect ValueError:
      writeTicketsForAreaFromStrings(tmpDir, "correct-area", docs, 1)

suite "executeManagerForArea":
  test "sets continuationPromptBuilder on AgentRunRequest":
    var capturedRequest: AgentRunRequest
    let capturingRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      capturedRequest = request
      AgentRunResult()

    let tmpDir = getTempDir() / "test_manager_continuation"
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    discard executeManagerForArea("test-area", "Area content.", tmpDir, 1, capturingRunner)
    check not capturedRequest.continuationPromptBuilder.isNil
