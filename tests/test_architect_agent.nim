## Unit tests for architect agent continuation prompt builder wiring.

import
  std/[os, tables, unittest],
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

suite "readSpecHashMarker":
  test "returns empty string when file does not exist":
    let tmpDir = getTempDir() / "test_spec_hash_missing"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    check readSpecHashMarker(tmpDir) == ""

  test "reads valid spec hash":
    let tmpDir = getTempDir() / "test_spec_hash_valid"
    createDir(tmpDir / "areas")
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "areas" / ".spec-hash", "abc123\n")
    check readSpecHashMarker(tmpDir) == "abc123"

  test "returns empty string for unreadable file":
    let tmpDir = getTempDir() / "test_spec_hash_unreadable"
    createDir(tmpDir / "areas")
    defer:
      setFilePermissions(tmpDir / "areas" / ".spec-hash", {fpUserRead, fpUserWrite})
      removeDir(tmpDir)
    writeFile(tmpDir / "areas" / ".spec-hash", "abc123\n")
    setFilePermissions(tmpDir / "areas" / ".spec-hash", {})
    check readSpecHashMarker(tmpDir) == ""

suite "readAreaHashes":
  test "returns empty table when file does not exist":
    let tmpDir = getTempDir() / "test_area_hashes_missing"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    check readAreaHashes(tmpDir).len == 0

  test "reads valid area hashes":
    let tmpDir = getTempDir() / "test_area_hashes_valid"
    createDir(tmpDir / "tickets")
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "tickets" / ".area-hashes", "core:abc123\nui:def456\n")
    let hashes = readAreaHashes(tmpDir)
    check hashes.len == 2
    check hashes["core"] == "abc123"
    check hashes["ui"] == "def456"

  test "skips corrupted lines gracefully":
    let tmpDir = getTempDir() / "test_area_hashes_corrupt"
    createDir(tmpDir / "tickets")
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "tickets" / ".area-hashes", "valid:hash\ngarbage\n\n:noid\nalso-valid:hash2\n")
    let hashes = readAreaHashes(tmpDir)
    check hashes.len == 2
    check hashes["valid"] == "hash"
    check hashes["also-valid"] == "hash2"

  test "returns empty table for unreadable file":
    let tmpDir = getTempDir() / "test_area_hashes_unreadable"
    createDir(tmpDir / "tickets")
    defer:
      setFilePermissions(tmpDir / "tickets" / ".area-hashes", {fpUserRead, fpUserWrite})
      removeDir(tmpDir)
    writeFile(tmpDir / "tickets" / ".area-hashes", "core:abc123\n")
    setFilePermissions(tmpDir / "tickets" / ".area-hashes", {})
    check readAreaHashes(tmpDir).len == 0
