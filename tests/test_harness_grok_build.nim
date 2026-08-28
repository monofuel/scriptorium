## Unit tests for the grok-build ACP harness.

import
  std/[json, os, sequtils, strutils, tempfiles, unittest],
  scriptorium/harness_grok_build

proc withTempHarnessDir(action: proc(tmpDir: string)) =
  ## Run action inside a temporary directory and remove it afterwards.
  let tmpDir = createTempDir("scriptorium_test_harness_grok_build_", "", getTempDir())
  defer:
    removeDir(tmpDir)
  action(tmpDir)

proc writeExecutableScript(path: string, body: string) =
  ## Write a bash script to path and mark it executable.
  let scriptContent = "#!/usr/bin/env bash\nset -euo pipefail\n" & body
  writeFile(path, scriptContent)
  setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec})

suite "harness grok-build":
  test "buildGrokBuildCmdArgs matches expected arg order":
    let request = GrokBuildRunRequest(
      model: "grok-4.6",
    )
    let args = buildGrokBuildCmdArgs(request)
    check args == @[
      "agent",
      "--always-approve",
      "--model",
      "grok-4.6",
      "stdio",
    ]

  test "buildGrokBuildCmdArgs includes reasoning effort when set":
    let request = GrokBuildRunRequest(
      model: "grok-4.6",
      reasoningEffort: "high",
    )
    let args = buildGrokBuildCmdArgs(request)
    check "--reasoning-effort" in args
    check "high" in args

  test "buildGrokBuildCmdArgs rejects empty model":
    let request = GrokBuildRunRequest(model: "")
    expect ValueError:
      discard buildGrokBuildCmdArgs(request)

  test "buildGrokBuildMcpServers builds http server with headers":
    let servers = buildGrokBuildMcpServers("http://127.0.0.1:8097")
    check servers.kind == JArray
    check servers.len == 1
    check servers[0]["type"].getStr() == "http"
    check servers[0]["name"].getStr() == "scriptorium"
    check servers[0]["url"].getStr() == "http://127.0.0.1:8097/mcp"
    check servers[0]["headers"].kind == JArray

  test "buildGrokBuildMcpServers trims trailing slash":
    let servers = buildGrokBuildMcpServers("http://127.0.0.1:8097/")
    check servers[0]["url"].getStr() == "http://127.0.0.1:8097/mcp"

  test "buildGrokBuildMcpServers empty endpoint yields empty array":
    check buildGrokBuildMcpServers("").len == 0
    check buildGrokBuildMcpServers("   ").len == 0

  test "buildGrokBuildStreamEvent maps agent_message_chunk":
    let line = """{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"ok"}}}}"""
    let event = buildGrokBuildStreamEvent(line)
    check event.kind == grokBuildEventMessage
    check event.text == "ok"

  test "buildGrokBuildStreamEvent maps agent_thought_chunk":
    let line = """{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"planning"}}}}"""
    let event = buildGrokBuildStreamEvent(line)
    check event.kind == grokBuildEventReasoning
    check event.text == "planning"

  test "buildGrokBuildStreamEvent maps tool_call":
    let line = """{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"tool_call","title":"Read","toolName":"read_file","rawInput":{"path":"src/foo.nim"}}}}"""
    let event = buildGrokBuildStreamEvent(line)
    check event.kind == grokBuildEventTool
    check event.text == "Read src/foo.nim"

  test "buildGrokBuildStreamEvent ignores non-update methods as status":
    let line = """{"jsonrpc":"2.0","method":"_x.ai/mcp/init_progress","params":{}}"""
    let event = buildGrokBuildStreamEvent(line)
    check event.kind == grokBuildEventStatus
    check event.text == "_x.ai/mcp/init_progress"

  test "runGrokBuild drives fake ACP agent to completion":
    withTempHarnessDir(proc(tmpDir: string) =
      # Separate python file so ACP stdin is not consumed by a shell heredoc.
      let pyPath = tmpDir / "fake_acp_agent.py"
      writeFile(pyPath, """
import json, sys

def read():
    line = sys.stdin.readline()
    if not line:
        return None
    return json.loads(line)

def write(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()

while True:
    msg = read()
    if msg is None:
        break
    mid = msg.get("id")
    method = msg.get("method")
    if method == "initialize":
        write({"jsonrpc":"2.0","id":mid,"result":{"protocolVersion":1,"agentCapabilities":{}}})
    elif method == "session/new":
        write({"jsonrpc":"2.0","id":mid,"result":{"sessionId":"sess-test"}})
    elif method == "session/prompt":
        write({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"sess-test","update":{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"thinking"}}}})
        write({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"sess-test","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"ok"}}}})
        write({"jsonrpc":"2.0","id":mid,"result":{"stopReason":"end_turn"}})
        break
""")
      let grokPath = tmpDir / "fake-grok-acp.sh"
      writeExecutableScript(grokPath, "exec python3 " & quoteShell(pyPath) & " \"$@\"\n")
      let worktreePath = tmpDir / "worktree"
      createDir(worktreePath)
      var events: seq[string] = @[]
      let request = GrokBuildRunRequest(
        prompt: "Say ok",
        workingDir: worktreePath,
        model: "grok-4.6",
        ticketId: "fake-acp",
        grokBuildBinary: grokPath,
        logRoot: tmpDir / "logs",
        hardTimeoutMs: 15_000,
        noOutputTimeoutMs: 10_000,
        onEvent: proc(event: GrokBuildStreamEvent) =
          events.add($event.kind & ":" & event.text),
      )
      let runResult = runGrokBuild(request)
      check runResult.exitCode == 0
      check runResult.lastMessage == "ok"
      check fileExists(runResult.logFile)
      check fileExists(runResult.lastMessageFile)
      check events.anyIt(it.startsWith("reasoning:"))
      check events.anyIt(it.startsWith("message:ok"))
    )

  test "runGrokBuild surfaces acp initialize errors":
    withTempHarnessDir(proc(tmpDir: string) =
      let pyPath = tmpDir / "fake_acp_fail.py"
      writeFile(pyPath, """
import json, sys
line = sys.stdin.readline()
msg = json.loads(line)
sys.stdout.write(json.dumps({"jsonrpc":"2.0","id":msg["id"],"error":{"code":-32600,"message":"boom","data":"nope"}}) + "\n")
sys.stdout.flush()
""")
      let grokPath = tmpDir / "fake-grok-fail.sh"
      writeExecutableScript(grokPath, "exec python3 " & quoteShell(pyPath) & " \"$@\"\n")
      let worktreePath = tmpDir / "worktree"
      createDir(worktreePath)
      let request = GrokBuildRunRequest(
        prompt: "hi",
        workingDir: worktreePath,
        model: "grok-4.6",
        ticketId: "fake-fail",
        grokBuildBinary: grokPath,
        logRoot: tmpDir / "logs",
        hardTimeoutMs: 10_000,
        noOutputTimeoutMs: 5_000,
      )
      let runResult = runGrokBuild(request)
      check runResult.exitCode != 0
    )
