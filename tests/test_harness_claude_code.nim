## Unit tests for the Claude Code process harness.

import
  std/[json, os, sequtils, strutils, tempfiles, unittest],
  scriptorium/harness_claude_code

proc withTempHarnessDir(action: proc(tmpDir: string)) =
  ## Run action inside a temporary directory and remove it afterwards.
  let tmpDir = createTempDir("scriptorium_test_harness_claude_code_", "", getTempDir())
  defer:
    removeDir(tmpDir)
  action(tmpDir)

proc writeExecutableScript(path: string, body: string) =
  ## Write a bash script to path and mark it executable.
  let scriptContent = "#!/usr/bin/env bash\nset -euo pipefail\n" & body
  writeFile(path, scriptContent)
  setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec})

proc newBaseRequest(tmpDir: string, claudePath: string, ticketId: string): ClaudeCodeRunRequest =
  ## Build a baseline Claude Code run request for fake harness tests.
  let worktreePath = tmpDir / "worktree"
  createDir(worktreePath)
  result = ClaudeCodeRunRequest(
    prompt: "Implement the task.",
    workingDir: worktreePath,
    model: "claude-opus-4-6",
    ticketId: ticketId,
    claudeCodeBinary: claudePath,
    logRoot: tmpDir / "logs",
  )

suite "harness claude-code":
  test "buildClaudeCodeExecArgs matches expected arg order":
    let request = ClaudeCodeRunRequest(
      model: "claude-opus-4-6",
    )

    let args = buildClaudeCodeExecArgs(request)
    check args == @[
      "--print",
      "--output-format", "stream-json",
      "--verbose",
      "--dangerously-skip-permissions",
      "--model", "claude-opus-4-6",
    ]

  test "buildClaudeCodeExecArgs includes effort when configured":
    let request = ClaudeCodeRunRequest(
      model: "claude-opus-4-6",
      reasoningEffort: "high",
    )

    let args = buildClaudeCodeExecArgs(request)
    check "--effort" in args
    check "high" in args

  test "buildClaudeCodeExecArgs includes mcp config when endpoint is configured":
    let request = ClaudeCodeRunRequest(
      model: "claude-opus-4-6",
      mcpEndpoint: "http://127.0.0.1:8097",
    )

    let args = buildClaudeCodeExecArgs(request)
    check "--mcp-config" in args
    var mcpConfigIdx = -1
    for i, arg in args:
      if arg == "--mcp-config":
        mcpConfigIdx = i
        break
    check mcpConfigIdx >= 0
    let mcpJson = parseJson(args[mcpConfigIdx + 1])
    check mcpJson["mcpServers"]["scriptorium"]["url"].getStr() == "http://127.0.0.1:8097/mcp"

  test "buildClaudeCodeExecArgs trims trailing slash from mcp endpoint":
    let request = ClaudeCodeRunRequest(
      model: "claude-opus-4-6",
      mcpEndpoint: "http://127.0.0.1:8097/",
    )

    let args = buildClaudeCodeExecArgs(request)
    var mcpConfigIdx = -1
    for i, arg in args:
      if arg == "--mcp-config":
        mcpConfigIdx = i
        break
    check mcpConfigIdx >= 0
    let mcpJson = parseJson(args[mcpConfigIdx + 1])
    check mcpJson["mcpServers"]["scriptorium"]["url"].getStr() == "http://127.0.0.1:8097/mcp"

  test "buildClaudeCodeExecArgs omits mcp config when endpoint is empty":
    let request = ClaudeCodeRunRequest(
      model: "claude-opus-4-6",
      mcpEndpoint: "",
    )

    let args = buildClaudeCodeExecArgs(request)
    check "--mcp-config" notin args

  test "buildClaudeCodeExecArgs rejects unsupported reasoning effort values":
    let request = ClaudeCodeRunRequest(
      model: "claude-opus-4-6",
      reasoningEffort: "xhigh",
    )
    expect ValueError:
      discard buildClaudeCodeExecArgs(request)

  test "buildMcpConfigJson produces valid json with correct url and type":
    let result = buildMcpConfigJson("http://127.0.0.1:8097")
    let parsed = parseJson(result)
    check parsed["mcpServers"]["scriptorium"]["url"].getStr() == "http://127.0.0.1:8097/mcp"
    check parsed["mcpServers"]["scriptorium"]["type"].getStr() == "http"

  test "buildMcpConfigJson returns empty for empty endpoint":
    check buildMcpConfigJson("") == ""
    check buildMcpConfigJson("   ") == ""

  test "buildClaudeCodeStreamEvent parses system init":
    let line = """{"type":"system","subtype":"init","model":"claude-opus-4-6","session_id":"abc"}"""
    let event = buildClaudeCodeStreamEvent(line)
    check event.kind == claudeCodeEventStatus
    check "claude-opus-4-6" in event.text

  test "buildClaudeCodeStreamEvent parses assistant thinking":
    let line = """{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"planning the work"}]}}"""
    let event = buildClaudeCodeStreamEvent(line)
    check event.kind == claudeCodeEventReasoning
    check event.text == "planning the work"

  test "buildClaudeCodeStreamEvent parses assistant tool_use with command summary":
    let line = """{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","id":"toolu_123","input":{"command":"ls"}}]}}"""
    let event = buildClaudeCodeStreamEvent(line)
    check event.kind == claudeCodeEventTool
    check event.text == "Bash ls"

  test "buildClaudeCodeStreamEvent parses assistant tool_use with file_path summary":
    let line = """{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","id":"toolu_456","input":{"file_path":"src/foo.nim","old_string":"x","new_string":"y"}}]}}"""
    let event = buildClaudeCodeStreamEvent(line)
    check event.kind == claudeCodeEventTool
    check event.text == "Edit src/foo.nim"

  test "buildClaudeCodeStreamEvent parses assistant tool_use without recognized args":
    let line = """{"type":"assistant","message":{"content":[{"type":"tool_use","name":"SubmitResult","id":"toolu_789","input":{"result":"done"}}]}}"""
    let event = buildClaudeCodeStreamEvent(line)
    check event.kind == claudeCodeEventTool
    check event.text == "SubmitResult"

  test "buildClaudeCodeStreamEvent truncates long command summary":
    let longCmd = "echo " & "x".repeat(100)
    let line = """{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","id":"toolu_000","input":{"command":"$1"}}]}}""".replace("$1", longCmd)
    let event = buildClaudeCodeStreamEvent(line)
    check event.kind == claudeCodeEventTool
    check event.text.len <= "Bash ".len + 80

  test "buildClaudeCodeStreamEvent parses assistant text":
    let line = """{"type":"assistant","message":{"content":[{"type":"text","text":"hello world"}]}}"""
    let event = buildClaudeCodeStreamEvent(line)
    check event.kind == claudeCodeEventMessage
    check event.text == "hello world"

  test "buildClaudeCodeStreamEvent parses user tool_result":
    let line = """{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_123","content":"ok","is_error":false}]}}"""
    let event = buildClaudeCodeStreamEvent(line)
    check event.kind == claudeCodeEventTool
    check "toolu_123" in event.text
    check "completed" in event.text

  test "buildClaudeCodeStreamEvent parses result success":
    let line = """{"type":"result","subtype":"success","is_error":false,"stop_reason":"end_turn","result":"done"}"""
    let event = buildClaudeCodeStreamEvent(line)
    check event.kind == claudeCodeEventStatus
    check "success" in event.text
    check "end_turn" in event.text

  test "buildClaudeCodeStreamEvent parses result error":
    let line = """{"type":"result","subtype":"error","is_error":true,"stop_reason":"","result":""}"""
    let event = buildClaudeCodeStreamEvent(line)
    check event.kind == claudeCodeEventStatus
    check "error" in event.text

  test "buildClaudeCodeStreamEvent handles malformed json":
    let event = buildClaudeCodeStreamEvent("not json at all")
    check event.kind == claudeCodeEventStatus
    check event.text == ""

  test "buildClaudeCodeStreamEvent handles empty line":
    let event = buildClaudeCodeStreamEvent("")
    check event.kind == claudeCodeEventStatus
    check event.text == ""

  test "extractLastMessageFromStream extracts final text from result":
    let output = """{"type":"system","subtype":"init","model":"claude-opus-4-6"}
{"type":"assistant","message":{"content":[{"type":"text","text":"hello world"}]}}
{"type":"result","subtype":"success","is_error":false,"result":"hello world","stop_reason":"end_turn"}
"""
    let msg = extractLastMessageFromStream(output)
    check msg == "hello world"

  test "extractLastMessageFromStream prefers result field":
    let output = """{"type":"assistant","message":{"content":[{"type":"text","text":"partial"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"final answer"}]}}
{"type":"result","subtype":"success","is_error":false,"result":"final answer","stop_reason":"end_turn"}
"""
    let msg = extractLastMessageFromStream(output)
    check msg == "final answer"

  test "extractLastMessageFromStream falls back to last assistant text":
    let output = """{"type":"assistant","message":{"content":[{"type":"text","text":"the answer"}]}}
"""
    let msg = extractLastMessageFromStream(output)
    check msg == "the answer"

  test "runClaudeCode captures output log and last message":
    withTempHarnessDir(proc(tmpDir: string) =
      let claudePath = tmpDir / "fake-claude.sh"
      writeExecutableScript(claudePath, """
cat >/dev/null
printf '{"type":"system","subtype":"init","model":"claude-opus-4-6"}\n'
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"hello world"}]}}\n'
printf '{"type":"result","subtype":"success","is_error":false,"result":"hello world","stop_reason":"end_turn"}\n'
""")

      let request = newBaseRequest(tmpDir, claudePath, "test-capture")
      let result = runClaudeCode(request)

      check result.exitCode == 0
      check result.timeoutKind == claudeCodeTimeoutNone
      check result.lastMessage == "hello world"
      check result.stdout.contains("""{"type":"result"""")
      check fileExists(result.logFile)
      check fileExists(result.lastMessageFile)
      check readFile(result.lastMessageFile) == "hello world"
    )

  test "runClaudeCode emits parsed stream events":
    withTempHarnessDir(proc(tmpDir: string) =
      let claudePath = tmpDir / "fake-claude.sh"
      writeExecutableScript(claudePath, """
cat >/dev/null
printf '{"type":"system","subtype":"init","model":"claude-opus-4-6"}\n'
printf '{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"planning"}]}}\n'
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","id":"t1","input":{"command":"ls"}}]}}\n'
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}\n'
printf '{"type":"result","subtype":"success","is_error":false,"result":"done","stop_reason":"end_turn"}\n'
""")

      var events: seq[string] = @[]
      var request = newBaseRequest(tmpDir, claudePath, "test-events")
      request.onEvent = proc(event: ClaudeCodeStreamEvent) =
        ## Capture events for assertion.
        events.add($event.kind & ":" & event.text)

      let result = runClaudeCode(request)
      check result.exitCode == 0
      check events.len >= 4
      check events.anyIt("reasoning" in it and "planning" in it)
      check events.anyIt("tool" in it and "Bash" in it)
      check events.anyIt("message" in it and "done" in it)
      check events.anyIt("status" in it and "success" in it)
    )

  test "runClaudeCode returns non-zero exit without retries by default":
    withTempHarnessDir(proc(tmpDir: string) =
      let claudePath = tmpDir / "fake-claude.sh"
      writeExecutableScript(claudePath, """
cat >/dev/null
printf '{"type":"result","subtype":"error","is_error":true,"result":"","stop_reason":"error"}\n'
exit 1
""")

      let request = newBaseRequest(tmpDir, claudePath, "test-fail")
      let result = runClaudeCode(request)

      check result.exitCode == 1
      check result.attemptCount == 1
    )

  test "runClaudeCode retries and uses continuation prompt":
    withTempHarnessDir(proc(tmpDir: string) =
      let claudePath = tmpDir / "fake-claude.sh"
      let markerPath = tmpDir / "attempt-marker"
      writeExecutableScript(claudePath, """
cat >/dev/null
marker=""" & "\"" & markerPath & "\"" & """

if [ ! -f "$marker" ]; then
  touch "$marker"
  printf '{"type":"result","subtype":"error","is_error":true,"result":"","stop_reason":"error"}\n'
  exit 1
else
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"fixed"}]}}\n'
  printf '{"type":"result","subtype":"success","is_error":false,"result":"fixed","stop_reason":"end_turn"}\n'
  exit 0
fi
""")

      var request = newBaseRequest(tmpDir, claudePath, "test-retry")
      request.maxAttempts = 2

      let result = runClaudeCode(request)
      check result.exitCode == 0
      check result.attemptCount == 2
      check result.lastMessage == "fixed"
    )

  test "runClaudeCode flags no-output timeout":
    withTempHarnessDir(proc(tmpDir: string) =
      let claudePath = tmpDir / "fake-claude.sh"
      writeExecutableScript(claudePath, """
cat >/dev/null
sleep 10
""")

      var request = newBaseRequest(tmpDir, claudePath, "test-no-output-timeout")
      request.noOutputTimeoutMs = 200

      let result = runClaudeCode(request)
      check result.timeoutKind == claudeCodeTimeoutNoOutput
    )

  test "runClaudeCode flags hard timeout":
    withTempHarnessDir(proc(tmpDir: string) =
      let claudePath = tmpDir / "fake-claude.sh"
      writeExecutableScript(claudePath, """
cat >/dev/null
while true; do
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"still going"}]}}\n'
  sleep 0.05
done
""")

      var request = newBaseRequest(tmpDir, claudePath, "test-hard-timeout")
      request.hardTimeoutMs = 300

      let result = runClaudeCode(request)
      check result.timeoutKind == claudeCodeTimeoutHard
    )
