## Live end-to-end integration test for a full Euler coding flow.

import
  std/[os, osproc, sequtils, strformat, strutils, unittest],
  ./support/live_integration_support

suite "integration e2e euler live":
  test "IT-LIVE-E2E-01 spec to done lands multiples.nim on master":
    doAssert findExe("codex").len > 0, "codex binary is required for live orchestrator integration"
    doAssert hasAgentAuth(),
      "agent auth is required for live orchestrator integration (set OPENAI_API_KEY, CODEX_API_KEY, or ANTHROPIC_API_KEY)"

    withTempLiveRepo("scriptorium_integration_live_euler_", proc(repoPath: string) =
      initLiveRepo(repoPath)
      addEulerMakefile(repoPath)

      let
        port = orchestratorPort(11)
        endpoint = &"http://127.0.0.1:{port}"
        specContent =
          "# Spec\n\n" &
          "## Goal\n" &
          "Add a Nim program named `multiples.nim` that solves Project Euler problem #1.\n\n" &
          "## Requirements\n" &
          "- Use Nim.\n" &
          "- The program must print only the answer number and a trailing newline.\n" &
          "- The answer must be the sum of all natural numbers below 1000 that are multiples of 3 or 5.\n" &
          "- Do not print explanatory text.\n" &
          "- Keep the implementation minimal.\n" &
          "- When complete, call the `submit_pr` tool.\n"
      writeSpecInPlan(repoPath, specContent, "integration-live-write-euler-spec")
      writeLiveConfig(repoPath, endpoint)

      let process = startOrchestrator(repoPath)
      defer:
        stopProcessWithSigint(process)

      let completed = waitForCondition(PositiveTimeoutMs, PollIntervalMs, proc(): bool =
        let files = planTreeFiles(repoPath)
        let doneTickets = files.filterIt(it.startsWith("tickets/done/") and it.endsWith(".md"))
        let (output, rc) = execCmdEx("git -C " & quoteShell(repoPath) & " show master:multiples.nim")
        discard output
        doneTickets.len > 0 and pendingQueueFiles(repoPath).len == 0 and rc == 0
      )
      doAssert completed,
        "orchestrator did not complete the live Euler flow.\n\n" &
        e2eDebugContext(repoPath)

      let planFiles = planTreeFiles(repoPath)
      let areaFiles = planFiles.filterIt(it.startsWith("areas/") and it.endsWith(".md"))
      let doneTickets = planFiles.filterIt(it.startsWith("tickets/done/") and it.endsWith(".md"))

      check areaFiles.len > 0
      check doneTickets.len > 0
      check pendingQueueFiles(repoPath).len == 0

      var sawSuccessNote = false
      for ticketPath in doneTickets:
        let doneContent = readPlanFile(repoPath, ticketPath)
        if "## Merge Queue Success" in doneContent:
          sawSuccessNote = true
      check sawSuccessNote

      let (_, masterProgramRc) = execCmdEx(
        "git -C " & quoteShell(repoPath) & " show master:multiples.nim"
      )
      doAssert masterProgramRc == 0, "master is missing multiples.nim.\n\n" & e2eDebugContext(repoPath)

      let (testOutput, testRc) = execCmdEx("cd " & quoteShell(repoPath) & " && make test")
      doAssert testRc == 0,
        "make test failed after live Euler flow.\n\n" &
        testOutput & "\n\n" &
        e2eDebugContext(repoPath)

      let (integrationOutput, integrationRc) = execCmdEx(
        "cd " & quoteShell(repoPath) & " && make integration-test"
      )
      doAssert integrationRc == 0,
        "make integration-test failed after live Euler flow.\n\n" &
        integrationOutput & "\n\n" &
        e2eDebugContext(repoPath)

      let (buildOutput, buildRc) = execCmdEx(
        "cd " & quoteShell(repoPath) &
        " && nim c --nimcache:.nimcache-verify -o:./multiples-verify-bin multiples.nim"
      )
      doAssert buildRc == 0,
        "nim c multiples.nim failed.\n\n" &
        buildOutput & "\n\n" &
        e2eDebugContext(repoPath)

      let (runOutput, runRc) = execCmdEx("cd " & quoteShell(repoPath) & " && ./multiples-verify-bin")
      doAssert runRc == 0,
        "running ./multiples-verify-bin failed.\n\n" &
        runOutput & "\n\n" &
        e2eDebugContext(repoPath)
      let outputLines = runOutput.splitLines().filterIt(it.strip().len > 0)
      doAssert outputLines.len > 0,
        "running ./multiples-verify-bin produced no output.\n\n" &
        runOutput & "\n\n" &
        e2eDebugContext(repoPath)
      check outputLines[^1].strip() == EulerExpectedAnswer
    )
