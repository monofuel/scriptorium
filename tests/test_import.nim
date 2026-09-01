## Unit tests for repository-to-spec import behavior.

import
  std/[os, strutils, unittest],
  scriptorium/[agent_runner, architect_agent, prompt_builders],
  helpers

suite "scriptorium import":
  test "import prompt reconciles reality while preserving plans":
    let prompt = buildArchitectImportPrompt(
      "/tmp/project",
      "/tmp/plan",
      "# Spec\n\n## Planned\n\nAdd a dashboard.\n",
    )

    check "/tmp/project" in prompt
    check "/tmp/plan" in prompt
    check "Add a dashboard." in prompt
    check "Correct stale or inaccurate descriptions" in prompt
    check "Preserve explicit future requirements" in prompt
    check "may write only `/tmp/plan/spec.md`" in prompt
    check "Do not start implementation work" in prompt

  test "import commits only a changed spec and is repeatable":
    let tmp = getTempDir() / "scriptorium_test_import_spec"
    makeInitializedTestRepo(tmp)
    defer: removeDir(tmp)
    writeSpecInPlan(tmp, "# Spec\n\n## Planned\n\nAdd a dashboard.\n")

    var calls = 0
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Reconcile the spec while attempting writes that import must discard.
      inc calls
      check tmp in request.prompt
      check "Add a dashboard." in request.prompt
      writeFile(
        request.workingDir / "spec.md",
        "# Spec\n\n## Current behavior\n\nImports repositories.\n\n## Planned\n\nAdd a dashboard.\n",
      )
      writeFile(request.workingDir / "areas" / "bad.md", "# Disallowed\n")
      writeFile(request.workingDir / "tickets" / "open" / "9999-bad.md", "# Disallowed\n")
      result = AgentRunResult(
        backend: harnessCodex,
        exitCode: 0,
        attempt: 1,
        attemptCount: 1,
        lastMessage: "Imported repository state.",
        timeoutKind: "none",
      )

    let before = planCommitCount(tmp)
    let changed = importSpecFromRepository(tmp, fakeRunner)
    let after = planCommitCount(tmp)
    let unchanged = importSpecFromRepository(tmp, fakeRunner)
    let afterUnchanged = planCommitCount(tmp)
    let files = planTreeFiles(tmp)

    check changed
    check not unchanged
    check calls == 2
    check after == before + 1
    check afterUnchanged == after
    check "areas/bad.md" notin files
    check "tickets/open/9999-bad.md" notin files
    check "Imports repositories." in readPlanFile(tmp, "spec.md")
    check latestPlanCommits(tmp, 1) == @[ImportSpecCommitMessage]

  test "import fails before invoking an agent when init is missing":
    let tmp = getTempDir() / "scriptorium_test_import_requires_init"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    var called = false
    proc fakeRunner(request: AgentRunRequest): AgentRunResult =
      ## Record an unexpected agent invocation.
      discard request
      called = true
      result = AgentRunResult()

    expect ValueError:
      discard importSpecFromRepository(tmp, fakeRunner)
    check not called
