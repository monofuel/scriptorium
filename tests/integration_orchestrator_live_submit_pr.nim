## Integration tests for live orchestrator daemon submit_pr flows.

import
  std/[os, osproc, strformat, strutils, times, unittest],
  ./support/live_integration_support

suite "integration orchestrator live submit_pr":
  test "IT-LIVE-03 real daemon path completes ticket via live submit_pr":
    doAssert findExe("codex").len > 0, "codex binary is required for live orchestrator integration"
    doAssert hasAgentAuth(),
      "agent auth is required for live orchestrator integration (set OPENAI_API_KEY, CODEX_API_KEY, or ANTHROPIC_API_KEY)"

    withTempLiveRepo("scriptorium_integration_live_it03_", proc(repoPath: string) =
      initLiveRepo(repoPath)
      addPassingMakefile(repoPath)

      let
        port = orchestratorPort(1)
        endpoint = &"http://127.0.0.1:{port}"
        timestamp = now().utc().format("yyyyMMddHHmmss")
        summaryNonce = &"it-live-03-{getCurrentProcessId()}-{timestamp}"
        ticketFile = "0001-live-submit-pr.md"
        openTicketPath = "tickets/open/" & ticketFile
        inProgressTicketPath = "tickets/in-progress/" & ticketFile
        doneTicketPath = "tickets/done/" & ticketFile
        ticketContent =
          "# Ticket 1\n\n" &
          "## Goal\n" &
          "Use the `submit_pr` function exactly once with summary `" & summaryNonce & "`.\n\n" &
          "## Requirements\n" &
          "- Do not edit repository files.\n" &
          "- Do not run shell commands to call submit_pr. Use the function from your tool list.\n" &
          "- After calling the function, reply with a short done message.\n\n" &
          "**Area:** 01-live\n"

      writeSpecInPlan(repoPath, "# Spec\n\nLive submit_pr runtime integration.\n", "integration-live-write-spec")
      addAreaToPlan(
        repoPath,
        "01-live.md",
        "# Area 01\n\n## Goal\n- Keep one live ticket for coding execution.\n",
        "integration-live-add-area",
      )
      addTicketToPlan(repoPath, ticketFile, ticketContent, "integration-live-add-ticket")

      writeLiveConfig(repoPath, endpoint)

      let process = startOrchestrator(repoPath)
      defer:
        stopProcessWithSigint(process)

      let completed = waitForCondition(PositiveTimeoutMs, PollIntervalMs, proc(): bool =
        let files = planTreeFiles(repoPath)
        doneTicketPath in files and
        openTicketPath notin files and
        inProgressTicketPath notin files and
        pendingQueueFiles(repoPath).len == 0
      )
      doAssert completed,
        "orchestrator did not reach done state for live submit_pr flow.\n" &
        "Plan files:\n" & planTreeFiles(repoPath).join("\n") & "\n\n" &
        "Log tail:\n" & orchestratorLogTail(repoPath)

      let doneContent = readPlanFile(repoPath, doneTicketPath)
      check "## Merge Queue Success" in doneContent
      check ("- Summary: " & summaryNonce) in doneContent

    )

  test "IT-LIVE-04 live daemon does not enqueue when submit_pr is missing":
    doAssert findExe("codex").len > 0, "codex binary is required for live orchestrator integration"
    doAssert hasAgentAuth(),
      "agent auth is required for live orchestrator integration (set OPENAI_API_KEY, CODEX_API_KEY, or ANTHROPIC_API_KEY)"

    withTempLiveRepo("scriptorium_integration_live_it04_", proc(repoPath: string) =
      initLiveRepo(repoPath)
      addPassingMakefile(repoPath)

      let
        port = orchestratorPort(2)
        endpoint = &"http://127.0.0.1:{port}"
        ticketFile = "0001-live-missing-submit-pr.md"
        openTicketPath = "tickets/open/" & ticketFile
        inProgressTicketPath = "tickets/in-progress/" & ticketFile
        doneTicketPath = "tickets/done/" & ticketFile
        ticketContent =
          "# Ticket 1\n\n" &
          "## Goal\n" &
          "Perform a no-op response.\n\n" &
          "**Area:** 01-live\n"

      writeSpecInPlan(repoPath, "# Spec\n\nLive missing-submit_pr integration.\n", "integration-live-write-spec")
      addAreaToPlan(
        repoPath,
        "01-live.md",
        "# Area 01\n\n## Goal\n- Keep one live ticket for coding execution.\n",
        "integration-live-add-area",
      )
      addTicketToPlan(repoPath, ticketFile, ticketContent, "integration-live-add-ticket")

      writeLiveConfig(repoPath, endpoint, "gpt-live-invalid-model-no-submit-pr")

      let process = startOrchestrator(repoPath)
      defer:
        stopProcessWithSigint(process)

      let runRecorded = waitForCondition(NegativeTimeoutMs, PollIntervalMs, proc(): bool =
        let files = planTreeFiles(repoPath)
        if inProgressTicketPath in files and openTicketPath notin files:
          let content = readPlanFile(repoPath, inProgressTicketPath)
          "## Agent Run" in content
        else:
          false
      )
      doAssert runRecorded,
        "orchestrator did not record a failed coding run for missing submit_pr scenario.\n" &
        "Plan files:\n" & planTreeFiles(repoPath).join("\n") & "\n\n" &
        "Log tail:\n" & orchestratorLogTail(repoPath)

      let files = planTreeFiles(repoPath)
      check doneTicketPath notin files
      check inProgressTicketPath in files
      check pendingQueueFiles(repoPath).len == 0

      let ticketContentAfterRun = readPlanFile(repoPath, inProgressTicketPath)
      check "## Agent Run" in ticketContentAfterRun
      check "- Exit Code: 0" notin ticketContentAfterRun
      check process.peekExitCode() == -1
    )
