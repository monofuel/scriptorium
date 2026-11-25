## Unit tests for per-area manager agent: prompt building and submit_tickets MCP state.

import
  std/[json, os, strutils, unittest],
  scriptorium/[agent_runner, manager_agent, mcp_server, prompt_builders, prompt_catalog, shared_state, ticket_metadata],
  helpers

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
      discard invokeAgentMcpTool(request.mcpEndpoint, "submit_tickets", %*{"tickets": []})
      AgentRunResult()

    let tmpDir = getTempDir() / "test_manager_continuation"
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    discard executeManagerForArea("test-area", "Area content.", tmpDir, 1, capturingRunner)
    check not capturedRequest.continuationPromptBuilder.isNil

  test "missing submit_tickets fails rather than silently marking an area planned":
    let tmpDir = getTempDir() / "test_manager_missing_submission"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let runner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      ## Return a native success without the required manager completion tool.
      AgentRunResult()
    expect ValueError:
      discard executeManagerForArea("core", "# Core", tmpDir, 1, runner)

suite "manager provisional ticket IDs":
  test "later batches retain their own dependency edges after global allocation":
    let documents = @["# 0001-execution-baseline\n\n**Area:** clock\n",
      "# 0002-clock-contract\n\n**Depends:** 0001\n\n**Area:** clock\n"]
    let rebased = relocateManagerTickets(documents, 1, 10)
    check rebased[0].startsWith("# 0010-execution-baseline")
    check rebased[1].startsWith("# 0011-clock-contract")
    check parseDependsFromTicketContent(rebased[1]) == @["0010"]

  test "pre-existing external dependencies remain exact while internal references move":
    let documents = @["# 0010 First\n\n**Depends:** 0001\n",
      "# 0011 Second\n\n**Depends:** 0002, 0010\n"]
    let rebased = relocateManagerTickets(documents, 10, 25)
    check parseDependsFromTicketContent(rebased[0]) == @["0001"]
    check parseDependsFromTicketContent(rebased[1]) == @["0002", "0025"]

  test "unknown provisional references and self-dependencies are rejected before writing":
    expect ValueError:
      discard relocateManagerTickets(@["# First\n\n**Depends:** 0001\n"], 1, 10)
    expect ValueError:
      discard relocateManagerTickets(@["# First\n\n**Depends:** 0099\n"], 1, 10)

  test "the ticket writer consumes the same rebased documents":
    let tmpDir = getTempDir() / "test_manager_rebased_write"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeTicketsForAreaFromStrings(tmpDir, "clock", @["# 0001 First", "# 0002 Second\n\n**Depends:** 0001"], 10, 1)
    let content = readFile(tmpDir / "tickets/open/0011-0011-second.md")
    check parseDependsFromTicketContent(content) == @["0010"]

suite "serial manager persistence":
  test "the second manager sees committed first tickets and a fresh global ID base":
    withInitializedTempRepo("manager_serial_ids_", proc(repo: string) =
      discard withLockedPlanWorktree(repo, proc(plan: string): bool =
        ## Create only synthetic specification and area inputs.
        writeFile(plan / "spec.md", "# Synthetic specification\n")
        writeFile(plan / "areas/first.md", "# First area\n")
        writeFile(plan / "areas/second.md", "# Second area\n")
        writeAreaHashes(plan, initTable[string, string]())
        gitRun(plan, "add", "spec.md", "areas", "tickets")
        gitRun(plan, "commit", "-m", "synthetic manager inputs")
        true)
      var calls = 0
      let runner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
        ## Submit actual scoped MCP completions while inspecting the prior committed area result.
        inc calls
        if calls == 1:
          check "Start IDs at 0001" in request.prompt
          discard invokeAgentMcpTool(request.mcpEndpoint, "submit_tickets",
            %*{"tickets": ["# 0001 First\n\n**Area:** first"]})
        else:
          check "Start IDs at 0002" in request.prompt
          check gitCheck(repo, "cat-file", "-e", "scriptorium/plan:tickets/open/0001-0001-first.md") == 0
          discard invokeAgentMcpTool(request.mcpEndpoint, "submit_tickets",
            %*{"tickets": ["# 0002 Second\n\n**Depends:** 0001\n\n**Area:** second"]})
        AgentRunResult()
      check runManagerForAreas(repo, runner)
      check calls == 2
      let content = gitRunCapture(repo, @["show", "scriptorium/plan:tickets/open/0002-0002-second.md"]).output
      check parseDependsFromTicketContent(content) == @["0001"]
    )
