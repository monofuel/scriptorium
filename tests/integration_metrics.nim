## Integration tests for ticket prediction with plan branch operations.

import
  std/[os, osproc, strutils, unittest],
  scriptorium/[agent_runner, config, orchestrator],
  helpers

suite "ticket difficulty prediction":
  test "runTicketPrediction appends prediction to ticket markdown":
    withInitializedTempRepo("scriptorium_test_prediction_", proc(repoPath: string) =
      addTicketToPlan(repoPath, "in-progress", "0099-pred.md",
        "# Predict Me\n\n**Area:** test-area\n\n**Worktree:** /tmp/fake\n")

      proc predictionRunner(request: AgentRunRequest): AgentRunResult =
        ## Return a fake prediction response.
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 0,
          attempt: 1,
          attemptCount: 1,
          lastMessage: """{"predicted_difficulty": "easy", "predicted_duration_minutes": 15, "reasoning": "Small isolated change."}""",
          timeoutKind: "none",
        )

      runTicketPrediction(repoPath, "tickets/in-progress/0099-pred.md", predictionRunner)

      let (ticketContent, rc) = execCmdEx(
        "git -C " & quoteShell(repoPath) & " show scriptorium/plan:tickets/in-progress/0099-pred.md"
      )
      check rc == 0
      check "## Prediction" in ticketContent
      check "- predicted_difficulty: easy" in ticketContent
      check "- predicted_duration_minutes: 15" in ticketContent
    )

  test "runTicketPrediction logs warning and continues on failure":
    withInitializedTempRepo("scriptorium_test_prediction_fail_", proc(repoPath: string) =
      addTicketToPlan(repoPath, "in-progress", "0098-predfail.md",
        "# Predict Fail\n\n**Area:** test-area\n\n**Worktree:** /tmp/fake\n")

      proc failRunner(request: AgentRunRequest): AgentRunResult =
        ## Return a failing result to test best-effort behavior.
        result = AgentRunResult(
          backend: harnessCodex,
          exitCode: 1,
          attempt: 1,
          attemptCount: 1,
          lastMessage: "",
          timeoutKind: "none",
        )

      # Should not raise - prediction is best-effort.
      runTicketPrediction(repoPath, "tickets/in-progress/0098-predfail.md", failRunner)

      let (ticketContent, rc) = execCmdEx(
        "git -C " & quoteShell(repoPath) & " show scriptorium/plan:tickets/in-progress/0098-predfail.md"
      )
      check rc == 0
      check "## Prediction" notin ticketContent
    )
