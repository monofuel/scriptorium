## Live end-to-end integration test for a full Euler coding flow.

import
  std/[os, osproc, sequtils, strformat, strutils, unittest],
  ./support/live_integration_support

suite "integration e2e euler live":
  test "IT-LIVE-E2E-01 spec to done lands multiples.nim on master":
    doAssert findExe("codex").len > 0, "codex binary is required for live orchestrator integration"
    doAssert hasCodexAuth(),
      "OPENAI_API_KEY/CODEX_API_KEY or a Codex OAuth auth file is required for live orchestrator integration (" &
      codexAuthPath() & ")"

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
        "orchestrator did not complete the live Euler flow.\n" &
        "Plan files:\n" & planTreeFiles(repoPath).join("\n") & "\n\n" &
        "Log tail:\n" & orchestratorLogTail(repoPath)

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
      doAssert masterProgramRc == 0, "master is missing multiples.nim"

      let (testOutput, testRc) = execCmdEx("cd " & quoteShell(repoPath) & " && make test")
      doAssert testRc == 0, "make test failed after live Euler flow.\n" & testOutput

      let (integrationOutput, integrationRc) = execCmdEx(
        "cd " & quoteShell(repoPath) & " && make integration-test"
      )
      doAssert integrationRc == 0,
        "make integration-test failed after live Euler flow.\n" & integrationOutput

      let (runOutput, runRc) = execCmdEx("cd " & quoteShell(repoPath) & " && nim r multiples.nim")
      doAssert runRc == 0, "nim r multiples.nim failed.\n" & runOutput
      let outputLines = runOutput.splitLines().filterIt(it.strip().len > 0)
      doAssert outputLines.len > 0, "nim r multiples.nim produced no output.\n" & runOutput
      check outputLines[^1].strip() == EulerExpectedAnswer
    )
