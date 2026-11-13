## Unit tests for the log_forwarding module.

import
  std/[options, strutils, unittest],
  acport,
  scriptorium/[agent_runner, log_forwarding, logging]

suite "forwardAgentEvent":
  setup:
    captureLogs = true
    capturedLogs = @[]

  teardown:
    captureLogs = false
    capturedLogs = @[]

  test "tool event logs tool line":
    let event = AgentStreamEvent(kind: agentEventTool, text: "Grep pattern")
    forwardAgentEvent("coding", "T-001", event)
    check capturedLogs.len == 1
    check capturedLogs[0].msg.contains("coding[T-001]: tool Grep pattern")

  test "tool event with file activity logs two lines":
    let event = AgentStreamEvent(kind: agentEventTool, text: "Read src/main.nim",
      update: SessionUpdate(kind: toolCall, tool: ToolCall(kind: "read",
        locations: some(@[ToolLocation(path: "src/main.nim")]))))
    forwardAgentEvent("coding", "T-002", event)
    check capturedLogs.len == 2
    check capturedLogs[0].msg.contains("coding[T-002]: tool Read src/main.nim")
    check capturedLogs[1].msg.contains("coding[T-002]: file read src/main.nim")

  test "status event logs status line":
    let event = AgentStreamEvent(kind: agentEventStatus, text: "running")
    forwardAgentEvent("manager", "area-1", event)
    check capturedLogs.len == 1
    check capturedLogs[0].msg.contains("manager[area-1]: status running")

  test "heartbeat event is skipped":
    let event = AgentStreamEvent(kind: agentEventHeartbeat, text: "pulse")
    forwardAgentEvent("coding", "T-003", event)
    check capturedLogs.len == 0

  test "reasoning event is skipped":
    let event = AgentStreamEvent(kind: agentEventReasoning, text: "thinking...")
    forwardAgentEvent("coding", "T-004", event)
    check capturedLogs.len == 0

  test "message event is skipped":
    let event = AgentStreamEvent(kind: agentEventMessage, text: "done")
    forwardAgentEvent("coding", "T-005", event)
    check capturedLogs.len == 0
