## Unit tests for the typoi process harness.

import
  std/[os, sequtils, strutils, tempfiles, unittest],
  scriptorium/harness_typoi

proc withTempHarnessDir(action: proc(tmpDir: string)) =
  ## Run action inside a temporary directory and remove it afterwards.
  let tmpDir = createTempDir("scriptorium_test_harness_typoi_", "", getTempDir())
  defer:
    removeDir(tmpDir)
  action(tmpDir)

proc writeExecutableScript(path: string, body: string) =
  ## Write a bash script to path and mark it executable.
  let scriptContent = "#!/usr/bin/env bash\nset -euo pipefail\n" & body
  writeFile(path, scriptContent)
  setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec})

proc newBaseRequest(tmpDir: string, typoiPath: string, ticketId: string): TypoiRunRequest =
  ## Build a baseline typoi run request for fake harness tests.
  let worktreePath = tmpDir / "worktree"
  createDir(worktreePath)
  result = TypoiRunRequest(
    prompt: "Implement the task.",
    workingDir: worktreePath,
    model: "test-model",
    ticketId: ticketId,
    typoiBinary: typoiPath,
    logRoot: tmpDir / "logs",
  )

suite "harness typoi":
  test "buildTypoiExecArgs matches expected arg order":
    let request = TypoiRunRequest(
      model: "test-model",
    )

    let args = buildTypoiExecArgs(request, "/tmp/last-message.txt")
    check args == @[
      "--json-stream",
      "--yolo",
      "--output-last-message",
      "/tmp/last-message.txt",
      "--model",
      "test-model",
    ]

  test "buildTypoiExecArgs includes mcp-server-url when endpoint configured":
    let request = TypoiRunRequest(
      model: "test-model",
      mcpEndpoint: "http://127.0.0.1:8097",
    )

    let args = buildTypoiExecArgs(request, "/tmp/last-message.txt")
    check "--mcp-server-url" in args
    check "http://127.0.0.1:8097/mcp" in args

  test "buildTypoiExecArgs trims trailing slash from mcp endpoint":
    let request = TypoiRunRequest(
      model: "test-model",
      mcpEndpoint: "http://127.0.0.1:8097/",
    )

    let args = buildTypoiExecArgs(request, "/tmp/last-message.txt")
    check "http://127.0.0.1:8097/mcp" in args

  test "buildTypoiExecArgs infers anthropic provider for claude models":
    let request = TypoiRunRequest(
      model: "claude-opus-4-6",
    )

    let args = buildTypoiExecArgs(request, "/tmp/last-message.txt")
    check "--provider" in args
    check "anthropic" in args

  test "buildTypoiExecArgs does not add provider for non-claude models":
    let request = TypoiRunRequest(
      model: "gpt-5.4",
    )

    let args = buildTypoiExecArgs(request, "/tmp/last-message.txt")
    check "--provider" notin args

  test "buildTypoiExecArgs omits mcp flag when no endpoint":
    let request = TypoiRunRequest(
      model: "test-model",
    )

    let args = buildTypoiExecArgs(request, "/tmp/last-message.txt")
    check "--mcp-server-url" notin args

  test "runTypoi captures output log and last message":
    withTempHarnessDir(proc(tmpDir: string) =
      let typoiPath = tmpDir / "fake-typoi-success.sh"
      writeExecutableScript(typoiPath, """
last_message=""
model=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message) last_message="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    *) shift ;;
  esac
done
prompt="$(cat)"
printf '{"type":"status","text":"init"}\n'
printf '{"type":"status","text":"ready"}\n'
printf '{"type":"message","text":"%s"}\n' "$prompt"
printf '{"type":"status","text":"done"}\n'
printf 'final:%s\n' "$model" > "$last_message"
""")

      let request = newBaseRequest(tmpDir, typoiPath, "ticket-success")
      let result = runTypoi(request)

      check result.exitCode == 0
      check result.attempt == 1
      check result.attemptCount == 1
      check result.timeoutKind == typoiTimeoutNone
      check fileExists(result.logFile)
      check result.stdout.contains("\"type\":\"message\"")
      check result.lastMessage.contains("final:test-model")
      check result.command.len > 0
      check result.command[0] == typoiPath
    )

  test "runTypoi emits parsed stream events":
    withTempHarnessDir(proc(tmpDir: string) =
      let typoiPath = tmpDir / "fake-typoi-events.sh"
      writeExecutableScript(typoiPath, """
last_message=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message) last_message="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cat >/dev/null
sleep 0.25
printf '{"type":"status","text":"init"}\n'
printf '{"type":"tool","name":"read_file","text":"src/main.nim"}\n'
printf '{"type":"message","text":"done"}\n'
printf '{"type":"status","text":"done"}\n'
printf 'done\n' > "$last_message"
""")

      var request = newBaseRequest(tmpDir, typoiPath, "ticket-events")
      request.heartbeatIntervalMs = 100
      var events: seq[string] = @[]
      request.onEvent = proc(event: TypoiStreamEvent) =
        ## Collect stream events for assertions.
        events.add($event.kind & ":" & event.text)

      let result = runTypoi(request)

      var sawHeartbeat = false
      var sawTool = false
      var sawMessage = false
      var sawStatus = false
      for event in events:
        if event.startsWith("heartbeat:"):
          sawHeartbeat = true
        if event.contains("tool:read_file"):
          sawTool = true
        if event.contains("message:done"):
          sawMessage = true
        if event.contains("status:init"):
          sawStatus = true

      check result.exitCode == 0
      check sawHeartbeat
      check sawTool
      check sawMessage
      check sawStatus
    )

  test "runTypoi handles malformed lines gracefully":
    withTempHarnessDir(proc(tmpDir: string) =
      let typoiPath = tmpDir / "fake-typoi-malformed.sh"
      writeExecutableScript(typoiPath, """
last_message=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message) last_message="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cat >/dev/null
printf 'this is not json\n'
printf '{"type":"message","text":"valid after malformed"}\n'
printf 'ok\n' > "$last_message"
""")

      let request = newBaseRequest(tmpDir, typoiPath, "ticket-malformed")
      let result = runTypoi(request)

      check result.exitCode == 0
      check result.timeoutKind == typoiTimeoutNone
      check result.stdout.contains("this is not json")
      check result.stdout.contains("\"valid after malformed\"")
      check result.lastMessage.contains("ok")
    )

  test "runTypoi returns non-zero exit without retries by default":
    withTempHarnessDir(proc(tmpDir: string) =
      let typoiPath = tmpDir / "fake-typoi-fail.sh"
      writeExecutableScript(typoiPath, """
last_message=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message) last_message="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cat >/dev/null
printf '{"type":"status","text":"error"}\n'
printf 'failed\n' > "$last_message"
exit 7
""")

      let request = newBaseRequest(tmpDir, typoiPath, "ticket-fail")
      let result = runTypoi(request)

      check result.exitCode == 7
      check result.attempt == 1
      check result.attemptCount == 1
      check result.timeoutKind == typoiTimeoutNone
      check result.lastMessage.contains("failed")
    )

  test "runTypoi retries with continuation prompt":
    withTempHarnessDir(proc(tmpDir: string) =
      let typoiPath = tmpDir / "fake-typoi-retry.sh"
      writeExecutableScript(typoiPath, """
last_message=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message) last_message="$2"; shift 2 ;;
    *) shift ;;
  esac
done
prompt="$(cat)"
prompt_file="${last_message%.last_message.txt}.prompt.txt"
printf '%s' "$prompt" > "$prompt_file"
if [[ "$last_message" == *"attempt-01.last_message.txt" ]]; then
  printf '{"type":"status","text":"error"}\n'
  printf 'first attempt failed\n' > "$last_message"
  exit 9
fi
printf '{"type":"message","text":"ok"}\n'
printf 'second attempt success\n' > "$last_message"
""")

      var request = newBaseRequest(tmpDir, typoiPath, "ticket-retry")
      request.maxAttempts = 2
      let result = runTypoi(request)
      let secondPromptPath = request.logRoot / "ticket-retry" / "attempt-02.prompt.txt"

      check result.exitCode == 0
      check result.attempt == 2
      check result.attemptCount == 2
      check result.timeoutKind == typoiTimeoutNone
      check fileExists(secondPromptPath)
      check readFile(secondPromptPath).contains("Attempt 1 failed")
    )

  test "runTypoi flags no-output timeout":
    withTempHarnessDir(proc(tmpDir: string) =
      let typoiPath = tmpDir / "fake-typoi-stall.sh"
      writeExecutableScript(typoiPath, """
cat >/dev/null
sleep 3
printf '{"type":"message","text":"late"}\n'
""")

      var request = newBaseRequest(tmpDir, typoiPath, "ticket-timeout-no-output")
      request.noOutputTimeoutMs = 150
      request.hardTimeoutMs = 2000
      let result = runTypoi(request)

      check result.timeoutKind == typoiTimeoutNoOutput
      check result.exitCode != 0
      check result.attemptCount == 1
    )

  test "runTypoi flags hard timeout":
    withTempHarnessDir(proc(tmpDir: string) =
      let typoiPath = tmpDir / "fake-typoi-hard-timeout.sh"
      writeExecutableScript(typoiPath, """
cat >/dev/null
while true; do
  printf '{"type":"message","text":"tick"}\n'
  sleep 0.05
done
""")

      var request = newBaseRequest(tmpDir, typoiPath, "ticket-timeout-hard")
      request.noOutputTimeoutMs = 0
      request.hardTimeoutMs = 250
      let result = runTypoi(request)

      check result.timeoutKind == typoiTimeoutHard
      check result.exitCode != 0
      check result.attemptCount == 1
    )
