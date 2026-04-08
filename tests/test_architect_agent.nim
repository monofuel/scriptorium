## Unit tests for architect agent continuation prompt builder wiring.

import
  std/[os, unittest],
  scriptorium/[agent_runner, architect_agent, config, shared_state]

suite "architect agent continuationPromptBuilder":
  test "runPlanArchitectRequest sets continuationPromptBuilder":
    var capturedRequest: AgentRunRequest
    let capturingRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      capturedRequest = request
      AgentRunResult()

    let tmpDir = getTempDir() / "test_plan_architect_continuation"
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    let agentCfg = AgentConfig(
      harness: harnessClaudeCode,
      model: "test-model",
    )
    discard runPlanArchitectRequest(
      capturingRunner, tmpDir, tmpDir, agentCfg, "test prompt", "test-ticket",
    )
    check not capturedRequest.continuationPromptBuilder.isNil

  test "runDoArchitectRequest sets continuationPromptBuilder":
    var capturedRequest: AgentRunRequest
    let capturingRunner: AgentRunner = proc(request: AgentRunRequest): AgentRunResult =
      capturedRequest = request
      AgentRunResult()

    let tmpDir = getTempDir() / "test_do_architect_continuation"
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    let agentCfg = AgentConfig(
      harness: harnessClaudeCode,
      model: "test-model",
    )
    discard runDoArchitectRequest(
      capturingRunner, tmpDir, agentCfg, "test prompt", "test-ticket",
    )
    check not capturedRequest.continuationPromptBuilder.isNil
