## Integration tests for Codex harness prerequisite failure behavior.

import
  std/[os, osproc, strutils, tempfiles, unittest]

proc runCmd(command: string): tuple[output: string, exitCode: int] =
  ## Run a shell command and return combined output with the exit code.
  result = execCmdEx(command)

proc buildCodexHarnessBinary(tmpDir: string): string =
  ## Compile tests/integration_codex_harness.nim into a temporary executable.
  result = tmpDir / "integration_codex_harness_bin"
  let compileCommand =
    "nim c -o:" & quoteShell(result) & " " & quoteShell("tests/integration_codex_harness.nim")
  let compileResult = runCmd(compileCommand)
  doAssert compileResult.exitCode == 0, compileResult.output

proc runHarnessWithEnv(
  binaryPath: string,
  pathValue: string,
  openAiKey: string,
  codexKey: string,
): tuple[output: string, exitCode: int] =
  ## Run the integration harness binary with a controlled environment.
  let command =
    "env -i " &
    "PATH=" & quoteShell(pathValue) & " " &
    "OPENAI_API_KEY=" & quoteShell(openAiKey) & " " &
    "CODEX_API_KEY=" & quoteShell(codexKey) & " " &
    quoteShell(binaryPath)
  result = runCmd(command)

proc writeExecutableScript(path: string, body: string) =
  ## Write a shell script to path and mark it executable.
  writeFile(path, "#!/usr/bin/env bash\nset -euo pipefail\n" & body)
  setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec})

suite "integration codex prerequisites":
  test "IT-07 fails clearly when codex binary is missing":
    let tmpDir = createTempDir("scriptorium_integration_codex_prereq_missing_bin_", "", getTempDir())
    defer:
      removeDir(tmpDir)

    let harnessBinary = buildCodexHarnessBinary(tmpDir)
    let runResult = runHarnessWithEnv(
      harnessBinary,
      tmpDir,
      "dummy-openai-key",
      "dummy-codex-key",
    )

    check runResult.exitCode != 0
    check "codex binary is required for integration tests" in runResult.output

  test "IT-07 fails clearly when API keys are missing":
    let tmpDir = createTempDir("scriptorium_integration_codex_prereq_missing_keys_", "", getTempDir())
    defer:
      removeDir(tmpDir)

    let fakeBinDir = tmpDir / "bin"
    createDir(fakeBinDir)
    writeExecutableScript(fakeBinDir / "codex", "exit 0\n")

    let harnessBinary = buildCodexHarnessBinary(tmpDir)
    let runResult = runHarnessWithEnv(harnessBinary, fakeBinDir, "", "")

    check runResult.exitCode != 0
    check "OPENAI_API_KEY or CODEX_API_KEY is required for integration tests" in runResult.output
