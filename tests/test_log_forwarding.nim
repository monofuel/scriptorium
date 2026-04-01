## Unit tests for the log_forwarding module.

import
  std/[strutils, unittest],
  scriptorium/[agent_runner, log_forwarding, logging]

suite "extractFileActivity":
  test "Read tool returns read activity":
    check extractFileActivity("Read src/main.nim") == "read src/main.nim"

  test "read_file tool returns read activity":
    check extractFileActivity("read_file config.toml") == "read config.toml"

  test "Edit tool returns write activity":
    check extractFileActivity("Edit src/module.nim") == "write src/module.nim"

  test "Write tool returns write activity":
    check extractFileActivity("Write src/new_file.nim") == "write src/new_file.nim"

  test "write_file tool returns write activity":
    check extractFileActivity("write_file output.json") == "write output.json"

  test "create_file tool returns write activity":
    check extractFileActivity("create_file src/new.nim") == "write src/new.nim"

  test "edit_file tool returns write activity":
    check extractFileActivity("edit_file src/fix.nim") == "write src/fix.nim"

  test "Bash with cat returns read activity":
    check extractFileActivity("Bash cat /etc/hosts") == "read /etc/hosts"

  test "Bash with touch returns write activity":
    check extractFileActivity("Bash touch newfile.txt") == "write newfile.txt"

  test "Bash with unknown command returns empty":
    check extractFileActivity("Bash echo hello") == ""

  test "unknown tool returns empty":
    check extractFileActivity("Grep pattern") == ""

  test "tool name only with no args returns empty":
    check extractFileActivity("Read") == ""

  test "empty string returns empty":
    check extractFileActivity("") == ""

  test "flag-like token is skipped":
    check extractFileActivity("Read --verbose src/main.nim") == "read src/main.nim"

  test "flag with dot is not matched as file path":
    check extractFileActivity("Read -flag.txt") == ""

  test "path with slash is detected":
    check extractFileActivity("Read src/deep/path") == "read src/deep/path"

  test "path with dot is detected":
    check extractFileActivity("Read config.toml") == "read config.toml"

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
    let event = AgentStreamEvent(kind: agentEventTool, text: "Read src/main.nim")
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
