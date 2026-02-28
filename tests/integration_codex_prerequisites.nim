## Integration tests for Codex harness prerequisite failure behavior.

import
  std/[os, osproc, strutils, tempfiles, unittest],
  jsony

type
  OAuthTokensJson = object
    access_token*: string

  OAuthAuthJson = object
    tokens*: OAuthTokensJson

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
  authFilePath: string,
  includeHostPath: bool = true,
): tuple[output: string, exitCode: int] =
  ## Run the integration harness binary with a controlled environment.
  let inheritedPath = if includeHostPath: getEnv("PATH", "") else: ""
  let fullPath =
    if pathValue.len > 0 and inheritedPath.len > 0:
      pathValue & ":" & inheritedPath
    elif pathValue.len > 0:
      pathValue
    else:
      inheritedPath
  let command =
    "env -i " &
    "PATH=" & quoteShell(fullPath) & " " &
    "OPENAI_API_KEY=" & quoteShell(openAiKey) & " " &
    "CODEX_API_KEY=" & quoteShell(codexKey) & " " &
    "CODEX_AUTH_FILE=" & quoteShell(authFilePath) & " " &
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
      tmpDir / "missing-auth.json",
      false,
    )

    check runResult.exitCode != 0
    check "codex binary is required for integration tests" in runResult.output

  test "IT-07 fails clearly when API keys and OAuth auth are missing":
    let tmpDir = createTempDir("scriptorium_integration_codex_prereq_missing_auth_", "", getTempDir())
    defer:
      removeDir(tmpDir)

    let fakeBinDir = tmpDir / "bin"
    createDir(fakeBinDir)
    writeExecutableScript(fakeBinDir / "codex", "exit 0\n")

    let harnessBinary = buildCodexHarnessBinary(tmpDir)
    let runResult = runHarnessWithEnv(harnessBinary, fakeBinDir, "", "", tmpDir / "missing-auth.json")

    check runResult.exitCode != 0
    check "OPENAI_API_KEY/CODEX_API_KEY or a Codex OAuth auth file is required for integration tests" in runResult.output

  test "IT-07 accepts OAuth auth file when API keys are missing":
    let tmpDir = createTempDir("scriptorium_integration_codex_prereq_oauth_", "", getTempDir())
    defer:
      removeDir(tmpDir)

    let fakeBinDir = tmpDir / "bin"
    createDir(fakeBinDir)
    writeExecutableScript(fakeBinDir / "codex", """
last_message=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message) last_message="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cat >/dev/null
    printf '{"type":"message","text":"ok"}\n'
    printf 'ok\n' > "$last_message"
""")

    let authFilePath = tmpDir / "oauth-auth.json"
    writeFile(authFilePath, toJson(OAuthAuthJson(tokens: OAuthTokensJson(access_token: "test"))))
    let harnessBinary = buildCodexHarnessBinary(tmpDir)
    let runResult = runHarnessWithEnv(harnessBinary, fakeBinDir, "", "", authFilePath)

    check runResult.exitCode == 0
    check "[OK] real codex exec one-shot smoke test" in runResult.output
