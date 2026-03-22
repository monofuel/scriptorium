## Unit tests for per-area manager agent: prompt building and ticket document parsing.

import
  std/[os, strutils, unittest],
  scriptorium/[manager_agent, prompt_builders, prompt_catalog, shared_state, ticket_metadata]

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

suite "parseTicketDocumentsFromOutput":
  test "extracts single fenced markdown block":
    let output = """Some preamble text.

```markdown
# Add User Auth

Implement user authentication.

**Area:** backend-api
```

Done.
"""
    let docs = parseTicketDocumentsFromOutput(output)
    check docs.len == 1
    check docs[0].contains("# Add User Auth")
    check docs[0].contains("Implement user authentication.")

  test "extracts multiple fenced markdown blocks":
    let output = """
```markdown
# First Ticket

Content one.
```

Some intermediate text.

```markdown
# Second Ticket

Content two.
```
"""
    let docs = parseTicketDocumentsFromOutput(output)
    check docs.len == 2
    check docs[0].contains("# First Ticket")
    check docs[1].contains("# Second Ticket")

  test "returns empty seq when no fenced blocks":
    let docs = parseTicketDocumentsFromOutput("just some text without fences")
    check docs.len == 0

  test "skips empty fenced blocks":
    let output = """
```markdown
```

```markdown
# Real Ticket

Content here.
```
"""
    let docs = parseTicketDocumentsFromOutput(output)
    check docs.len == 1
    check docs[0].contains("# Real Ticket")

  test "handles fenced block with no closing fence":
    let output = """
```markdown
# Unclosed Block

This block has no closing fence.
"""
    let docs = parseTicketDocumentsFromOutput(output)
    check docs.len == 1
    check docs[0].contains("# Unclosed Block")

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
