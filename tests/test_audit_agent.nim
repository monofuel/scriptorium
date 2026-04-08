## Unit tests for the audit agent module.

import
  std/[os, strutils, unittest],
  scriptorium/[agent_pool, audit_agent, prompt_builders, prompt_catalog, shared_state]

proc makeTempDir(prefix: string): string =
  ## Create a temporary directory for tests.
  result = getTempDir() / prefix & $getCurrentProcessId()
  createDir(result)

suite "audit agent prompt rendering":
  test "buildAuditAgentPrompt renders all placeholders":
    let prompt = buildAuditAgentPrompt(
      spec = "Feature A: does X",
      agentsMd = "Rule 1: use camelCase",
      lastAuditCommit = "abc123",
      diff = "+added a line",
    )
    check "Feature A: does X" in prompt
    check "Rule 1: use camelCase" in prompt
    check "abc123" in prompt
    check "+added a line" in prompt

  test "buildAuditAgentPrompt strips whitespace from inputs":
    let prompt = buildAuditAgentPrompt(
      spec = "  spec content  \n",
      agentsMd = " agents \n",
      lastAuditCommit = " abc ",
      diff = " +line ",
    )
    check "spec content" in prompt
    check "agents" in prompt
    check "abc" in prompt
    check "+line" in prompt

  test "renderPromptTemplate raises on empty template":
    expect(ValueError):
      discard renderPromptTemplate("", @[])

  test "renderPromptTemplate raises on missing placeholder":
    expect(ValueError):
      discard renderPromptTemplate("no placeholders here", @[(name: "missing", value: "val")])

suite "audit state persistence":
  test "loadAuditState returns empty when file missing":
    let tmpDir = makeTempDir("audit_state_load_")
    defer: removeDir(tmpDir)
    let state = loadAuditState(tmpDir)
    check state.lastAuditedCommit == ""

  test "saveAuditState and loadAuditState round-trip":
    let tmpDir = makeTempDir("audit_state_rt_")
    defer: removeDir(tmpDir)
    let original = AuditState(lastAuditedCommit: "deadbeef1234")
    saveAuditState(tmpDir, original)
    let loaded = loadAuditState(tmpDir)
    check loaded.lastAuditedCommit == "deadbeef1234"

  test "saveAuditState overwrites existing state":
    let tmpDir = makeTempDir("audit_state_ow_")
    defer: removeDir(tmpDir)
    saveAuditState(tmpDir, AuditState(lastAuditedCommit: "first"))
    saveAuditState(tmpDir, AuditState(lastAuditedCommit: "second"))
    let loaded = loadAuditState(tmpDir)
    check loaded.lastAuditedCommit == "second"

suite "audit report writing":
  test "writeAuditReport creates file with content":
    let tmpDir = makeTempDir("audit_report_cr_")
    defer: removeDir(tmpDir)
    let report = "## Spec Drift\n\nNo issues found."
    let reportPath = writeAuditReport(tmpDir, report)
    check fileExists(reportPath)
    check readFile(reportPath) == report
    check reportPath.endsWith(".md")

  test "writeAuditReport path includes audit log directory":
    let tmpDir = makeTempDir("audit_report_path_")
    defer: removeDir(tmpDir)
    let reportPath = writeAuditReport(tmpDir, "test")
    check "/logs/audit/" in reportPath.replace('\\', '/')

suite "audit report capture via shared state":
  test "recordAuditReport and consumeAuditReport round-trip":
    recordAuditReport("test report", "test-ticket")
    let report = consumeAuditReport("test-ticket")
    check report == "test report"

  test "consumeAuditReport clears after consumption":
    recordAuditReport("one-time report", "clear-test")
    discard consumeAuditReport("clear-test")
    let second = consumeAuditReport("clear-test")
    check second == ""

suite "agent role enum and pool":
  test "arAudit exists in AgentRole":
    let role: AgentRole = arAudit
    check $role == "arAudit"

  test "isAuditRunning returns false when pool is empty":
    check not isAuditRunning()
