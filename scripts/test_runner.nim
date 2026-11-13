import
  std/[algorithm, os, osproc, strutils]

type
  RunningTest = object
    process: Process
    path, logPath: string

proc main() =
  ## Run explicit test files with bounded parallel compilation and retained logs.
  let arguments = commandLineParams()
  if arguments.len == 0: raise newException(ValueError, "A test category or file is required")
  let
    category = arguments[0]
    compiler = getEnv("NIM", "nim")
    jobs = if category == "unit": 4 else: 1
    logRoot = getCurrentDir() / ".build" / "test-results" / category
  createDir(logRoot)
  var files: seq[string]
  if category in ["unit", "integration", "e2e"]:
    let prefix = if category == "unit": "test_" elif category == "integration": "integration_" else: "e2e_"
    for path in walkFiles("tests/" & prefix & "*.nim"):
      if path != "tests/integration_acp_harness.nim": files.add(path)
  else:
    files = @[category]
  files.sort()
  if files.len == 0: raise newException(ValueError, "No tests selected: " & category)
  var
    running: seq[RunningTest]
    nextFile = 0
    failures = 0
  while nextFile < files.len or running.len > 0:
    while nextFile < files.len and running.len < jobs:
      let
        path = files[nextFile]
        name = path.extractFilename().changeFileExt("") &
          (if arguments.len > 1: "-" & arguments[1] else: "")
        logPath = logRoot / (name & ".log")
        binary = getCurrentDir() / ".build" / "test-binaries" / name
      createDir(binary.parentDir)
      var command = quoteShell(compiler) & " r --hints:off --warnings:off " &
        "--nimcache:" & quoteShell(getCurrentDir() / ".build" / "test-cache" / name) &
        " -o:" & quoteShell(binary)
      if arguments.len > 1:
        doAssert arguments.len == 2 and arguments[1] in ["codex", "claude", "grok"],
          "The only extra test argument is an explicit ACP backend"
        command.add(" -d:AcpBackend=" & arguments[1])
      command.add(" " & quoteShell(path))
      command.add(" > " & quoteShell(logPath) & " 2>&1")
      let child = startProcess("/bin/sh", args = @["-c", command])
      running.add(RunningTest(process: child, path: path, logPath: logPath))
      inc nextFile
    var index = running.len - 1
    while index >= 0:
      let code = running[index].process.peekExitCode()
      if code != -1:
        let item = running[index]
        item.process.close()
        if code == 0:
          echo "[PASS] " & item.path
        else:
          inc failures
          echo "[FAIL] " & item.path & "; log: " & item.logPath
          let output = readFile(item.logPath)
          echo output[max(0, output.len - 8000)..^1]
        running.delete(index)
      dec index
    if running.len > 0: sleep(50)
  if failures > 0: quit(1)

main()
