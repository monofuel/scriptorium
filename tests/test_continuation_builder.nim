## Tests for continuation_builder module.

import
  std/[os, strutils, tempfiles, unittest],
  scriptorium/continuation_builder

suite "continuation builder":
  test "returns rules content when AGENTS.md exists":
    let tmpDir = createTempDir("scriptorium_cb_test_", "")
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "AGENTS.md", "# Project Rules\n\n- Rule one\n- Rule two\n")
    let output = buildAgentsReinjectPrompt(tmpDir)
    check "The following project rules from AGENTS.md must be followed:" in output
    check "Rule one" in output
    check "Rule two" in output
    check "Continue from the previous attempt" in output

  test "returns default text when AGENTS.md is missing":
    let tmpDir = createTempDir("scriptorium_cb_test_", "")
    defer: removeDir(tmpDir)
    let output = buildAgentsReinjectPrompt(tmpDir)
    check output == "Continue from the previous attempt and complete the ticket. When done, call the `submit_pr` MCP tool with a summary."

  test "truncates large AGENTS.md":
    let tmpDir = createTempDir("scriptorium_cb_test_", "")
    defer: removeDir(tmpDir)
    let largeContent = 'x'.repeat(5000)
    writeFile(tmpDir / "AGENTS.md", largeContent)
    let output = buildAgentsReinjectPrompt(tmpDir)
    check "(Rules truncated due to length.)" in output
    check "Continue from the previous attempt" in output
    check output.len < 5000 + 500
