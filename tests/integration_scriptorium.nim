## Tests for the scriptorium CLI: init, config, endpoint parsing, and default branch resolution.

import
  std/[json, os, osproc, strutils, tables, tempfiles, unittest],
  jsony,
  scriptorium/[config, init, orchestrator],
  helpers

suite "scriptorium init":
  test "creates scriptorium/plan branch":
    let tmp = getTempDir() / "scriptorium_test_init_branch"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    runInit(tmp, quiet = true)

    let (_, rc) = execCmdEx("git -C " & tmp & " rev-parse --verify scriptorium/plan")
    check rc == 0

  test "plan branch contains correct folder structure":
    let tmp = getTempDir() / "scriptorium_test_init_structure"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    runInit(tmp, quiet = true)

    let (files, _) = execCmdEx("git -C " & tmp & " ls-tree -r --name-only scriptorium/plan")
    check "spec.md" in files
    check "areas/.gitkeep" in files
    check "tickets/open/.gitkeep" in files
    check "tickets/in-progress/.gitkeep" in files
    check "tickets/done/.gitkeep" in files
    check "decisions/.gitkeep" in files

  test "raises on already initialized workspace":
    let tmp = getTempDir() / "scriptorium_test_init_dupe"
    makeTestRepo(tmp)
    defer: removeDir(tmp)

    runInit(tmp, quiet = true)
    expect ValueError:
      runInit(tmp, quiet = true)

  test "raises on non-git directory":
    let tmp = getTempDir() / "scriptorium_test_not_a_repo"
    createDir(tmp)
    defer: removeDir(tmp)

    expect ValueError:
      runInit(tmp, quiet = true)

suite "config":
  test "defaults to claude models with claude-code harness for all roles":
    let cfg = defaultConfig()
    check cfg.agents.architect.model == "claude-opus-4-6"
    check cfg.agents.coding.model == "claude-sonnet-4-6"
    check cfg.agents.manager.model == "claude-sonnet-4-6"
    check cfg.agents.reviewer.model == "claude-sonnet-4-6"
    check cfg.agents.architect.harness == harnessClaudeCode
    check cfg.agents.coding.harness == harnessClaudeCode
    check cfg.agents.manager.harness == harnessClaudeCode
    check cfg.agents.reviewer.harness == harnessClaudeCode
    check cfg.agents.architect.reasoningEffort == ""
    check cfg.agents.coding.reasoningEffort == ""
    check cfg.agents.manager.reasoningEffort == ""
    check cfg.agents.reviewer.reasoningEffort == ""

  test "loads from scriptorium.json":
    let tmp = getTempDir() / "scriptorium_test_config"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.agents.architect = AgentConfig(harness: harnessClaudeCode, model: "claude-opus-4-6", reasoningEffort: "medium")
    writtenCfg.agents.coding = AgentConfig(harness: harnessTypoi, model: "grok-code-fast-1", reasoningEffort: "high")
    writtenCfg.agents.manager = AgentConfig(harness: harnessCodex, model: "gpt-5.1-codex-mini", reasoningEffort: "low")
    writtenCfg.endpoints.local = "http://localhost:1234/v1"
    writeScriptoriumConfig(tmp, writtenCfg)

    let cfg = loadConfig(tmp)
    check cfg.agents.architect.model == "claude-opus-4-6"
    check cfg.agents.architect.harness == harnessClaudeCode
    check cfg.agents.coding.model == "grok-code-fast-1"
    check cfg.agents.coding.harness == harnessTypoi
    check cfg.agents.manager.model == "gpt-5.1-codex-mini"
    check cfg.agents.manager.harness == harnessCodex
    check cfg.agents.architect.reasoningEffort == "medium"
    check cfg.agents.coding.reasoningEffort == "high"
    check cfg.agents.manager.reasoningEffort == "low"
    check cfg.endpoints.local == "http://localhost:1234/v1"

  test "loads reviewer config from scriptorium.json":
    let tmp = getTempDir() / "scriptorium_test_config_reviewer"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.agents.reviewer = AgentConfig(harness: harnessClaudeCode, model: "claude-sonnet-4-6", reasoningEffort: "low")
    writeScriptoriumConfig(tmp, writtenCfg)

    let cfg = loadConfig(tmp)
    check cfg.agents.reviewer.model == "claude-sonnet-4-6"
    check cfg.agents.reviewer.harness == harnessClaudeCode
    check cfg.agents.reviewer.reasoningEffort == "low"

  test "inferHarness works for reviewer models":
    check inferHarness("claude-sonnet-4-6") == harnessClaudeCode
    check inferHarness("codex-mini-review") == harnessCodex
    check inferHarness("grok-review-1") == harnessTypoi

  test "manager model remains independent when manager is unset":
    let tmp = getTempDir() / "scriptorium_test_config_manager_independent"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.agents.coding = AgentConfig(harness: harnessTypoi, model: "grok-code-fast-1", reasoningEffort: "high")
    writtenCfg.agents.manager = AgentConfig()
    writeScriptoriumConfig(tmp, writtenCfg)

    let cfg = loadConfig(tmp)
    check cfg.agents.coding.model == "grok-code-fast-1"
    check cfg.agents.manager.model == "claude-sonnet-4-6"
    check cfg.agents.coding.reasoningEffort == "high"
    check cfg.agents.manager.reasoningEffort == ""

  test "missing file returns defaults":
    let tmp = getTempDir() / "scriptorium_test_config_missing"
    createDir(tmp)
    defer: removeDir(tmp)

    let cfg = loadConfig(tmp)
    check cfg.agents.architect.model == "claude-opus-4-6"
    check cfg.agents.coding.model == "claude-sonnet-4-6"
    check cfg.agents.manager.model == "claude-sonnet-4-6"
    check cfg.agents.architect.reasoningEffort == ""
    check cfg.agents.coding.reasoningEffort == ""
    check cfg.agents.manager.reasoningEffort == ""

  test "inferHarness routing":
    check inferHarness("claude-opus-4-6") == harnessClaudeCode
    check inferHarness("claude-haiku-4-5") == harnessClaudeCode
    check inferHarness("codex-mini") == harnessCodex
    check inferHarness("gpt-4o") == harnessCodex
    check inferHarness("grok-code-fast-1") == harnessTypoi
    check inferHarness("local/qwen3.5-35b-a3b") == harnessTypoi

  test "concurrency defaults when key is absent":
    let tmp = getTempDir() / "scriptorium_test_config_concurrency_absent"
    createDir(tmp)
    defer: removeDir(tmp)

    let cfg = loadConfig(tmp)
    check cfg.concurrency.maxAgents == 4
    check cfg.concurrency.tokenBudgetMB == 0

  test "concurrency parses both keys":
    let tmp = getTempDir() / "scriptorium_test_config_concurrency_both"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.concurrency.maxAgents = 4
    writtenCfg.concurrency.tokenBudgetMB = 512
    writeScriptoriumConfig(tmp, writtenCfg)

    let cfg = loadConfig(tmp)
    check cfg.concurrency.maxAgents == 4
    check cfg.concurrency.tokenBudgetMB == 512

  test "concurrency parses only maxAgents":
    let tmp = getTempDir() / "scriptorium_test_config_concurrency_maxonly"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.concurrency.maxAgents = 8
    writeScriptoriumConfig(tmp, writtenCfg)

    let cfg = loadConfig(tmp)
    check cfg.concurrency.maxAgents == 8
    check cfg.concurrency.tokenBudgetMB == 0

  test "timeout defaults when key is absent":
    let tmp = getTempDir() / "scriptorium_test_config_timeout_absent"
    createDir(tmp)
    defer: removeDir(tmp)

    let cfg = loadConfig(tmp)
    check cfg.timeouts.codingAgentHardTimeoutMs == 14_400_000
    check cfg.timeouts.codingAgentNoOutputTimeoutMs == 300_000
    check cfg.timeouts.codingAgentProgressTimeoutMs == 600_000
    check cfg.timeouts.codingAgentMaxAttempts == 5

  test "timeout parses custom values":
    let tmp = getTempDir() / "scriptorium_test_config_timeout_custom"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.timeouts.codingAgentHardTimeoutMs = 7_200_000
    writtenCfg.timeouts.codingAgentNoOutputTimeoutMs = 600_000
    writtenCfg.timeouts.codingAgentProgressTimeoutMs = 900_000
    writtenCfg.timeouts.codingAgentMaxAttempts = 3
    writeScriptoriumConfig(tmp, writtenCfg)

    let cfg = loadConfig(tmp)
    check cfg.timeouts.codingAgentHardTimeoutMs == 7_200_000
    check cfg.timeouts.codingAgentNoOutputTimeoutMs == 600_000
    check cfg.timeouts.codingAgentProgressTimeoutMs == 900_000
    check cfg.timeouts.codingAgentMaxAttempts == 3

  test "default endpoint populated when not in scriptorium.json":
    let tmp = getTempDir() / "scriptorium_test_config_endpoint_default"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.endpoints.local = ""
    writeScriptoriumConfig(tmp, writtenCfg)

    let cfg = loadConfig(tmp)
    check cfg.endpoints.local == "http://127.0.0.1:8097"

  test "missing file returns default endpoint":
    let tmp = getTempDir() / "scriptorium_test_config_endpoint_missing"
    createDir(tmp)
    defer: removeDir(tmp)

    let cfg = loadConfig(tmp)
    check cfg.endpoints.local == "http://127.0.0.1:8097"

  test "defaultConfig has syncAgentsMd true":
    let cfg = defaultConfig()
    check cfg.syncAgentsMd == true

  test "loadConfig with syncAgentsMd false returns false":
    let tmp = getTempDir() / "scriptorium_test_config_sync_false"
    createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "scriptorium.json", """{"syncAgentsMd": false}""")

    let cfg = loadConfig(tmp)
    check cfg.syncAgentsMd == false

  test "loadConfig without syncAgentsMd key returns true":
    let tmp = getTempDir() / "scriptorium_test_config_sync_missing"
    createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "scriptorium.json", """{}""")

    let cfg = loadConfig(tmp)
    check cfg.syncAgentsMd == true

  test "default audit model is claude-haiku-4-5-20251001":
    let cfg = defaultConfig()
    check cfg.agents.audit.model == "claude-haiku-4-5-20251001"
    check cfg.agents.audit.harness == harnessClaudeCode

  test "audit config overrides from JSON":
    let tmp = getTempDir() / "scriptorium_test_config_audit_override"
    createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "scriptorium.json", """{"agents": {"audit": {"model": "claude-sonnet-4-6"}}}""")

    let cfg = loadConfig(tmp)
    check cfg.agents.audit.model == "claude-sonnet-4-6"
    check cfg.agents.audit.harness == harnessClaudeCode

  test "loop defaults when key is absent":
    let tmp = getTempDir() / "scriptorium_test_config_loop_absent"
    createDir(tmp)
    defer: removeDir(tmp)

    let cfg = loadConfig(tmp)
    check cfg.loop.enabled == false
    check cfg.loop.feedback == ""
    check cfg.loop.goal == ""
    check cfg.loop.maxIterations == 0

  test "loop parses all fields from JSON":
    let tmp = getTempDir() / "scriptorium_test_config_loop_full"
    createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "scriptorium.json", """{"loop": {"enabled": true, "feedback": "make bench", "goal": "optimize latency", "maxIterations": 5}}""")

    let cfg = loadConfig(tmp)
    check cfg.loop.enabled == true
    check cfg.loop.feedback == "make bench"
    check cfg.loop.goal == "optimize latency"
    check cfg.loop.maxIterations == 5

  test "audit config defaults when absent from JSON":
    let tmp = getTempDir() / "scriptorium_test_config_audit_absent"
    createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "scriptorium.json", """{"agents": {"coding": {"model": "claude-sonnet-4-6"}}}""")

    let cfg = loadConfig(tmp)
    check cfg.agents.audit.model == "claude-haiku-4-5-20251001"
    check cfg.agents.audit.harness == harnessClaudeCode

suite "orchestrator endpoint":
  test "empty endpoint falls back to default":
    let endpoint = parseEndpoint("")
    check endpoint.address == "127.0.0.1"
    check endpoint.port == 8097

  test "parses endpoint from config value":
    let tmp = getTempDir() / "scriptorium_test_orchestrator_endpoint"
    createDir(tmp)
    defer: removeDir(tmp)
    var writtenCfg = defaultConfig()
    writtenCfg.endpoints.local = "http://localhost:1234/v1"
    writeScriptoriumConfig(tmp, writtenCfg)

    let endpoint = loadOrchestratorEndpoint(tmp)
    check endpoint.address == "localhost"
    check endpoint.port == 1234

  test "rejects endpoint missing host":
    expect ValueError:
      discard parseEndpoint("http:///v1")

suite "resolveDefaultBranch":
  test "detects master when it exists":
    let tmp = getTempDir() / "scriptorium_test_resolve_master"
    if dirExists(tmp):
      removeDir(tmp)
    createDir(tmp)
    defer:
      removeDir(tmp)
    discard execCmdEx("git -C " & tmp & " init")
    discard execCmdEx("git -C " & tmp & " config user.email test@test.com")
    discard execCmdEx("git -C " & tmp & " config user.name Test")
    discard execCmdEx("git -C " & tmp & " commit --allow-empty -m initial")
    check resolveDefaultBranch(tmp) == "master"

  test "detects main when master does not exist":
    let tmp = getTempDir() / "scriptorium_test_resolve_main"
    if dirExists(tmp):
      removeDir(tmp)
    createDir(tmp)
    defer:
      removeDir(tmp)
    discard execCmdEx("git -C " & tmp & " init -b main")
    discard execCmdEx("git -C " & tmp & " config user.email test@test.com")
    discard execCmdEx("git -C " & tmp & " config user.name Test")
    discard execCmdEx("git -C " & tmp & " commit --allow-empty -m initial")
    check resolveDefaultBranch(tmp) == "main"

  test "errors when no known default branch exists":
    let tmp = getTempDir() / "scriptorium_test_resolve_none"
    if dirExists(tmp):
      removeDir(tmp)
    createDir(tmp)
    defer:
      removeDir(tmp)
    discard execCmdEx("git -C " & tmp & " init -b feature")
    discard execCmdEx("git -C " & tmp & " config user.email test@test.com")
    discard execCmdEx("git -C " & tmp & " config user.name Test")
    discard execCmdEx("git -C " & tmp & " commit --allow-empty -m initial")
    expect IOError:
      discard resolveDefaultBranch(tmp)

  test "prefers origin/HEAD when set":
    let tmp = getTempDir() / "scriptorium_test_resolve_origin_head"
    if dirExists(tmp):
      removeDir(tmp)
    createDir(tmp)
    defer:
      removeDir(tmp)
    discard execCmdEx("git -C " & tmp & " init -b main")
    discard execCmdEx("git -C " & tmp & " config user.email test@test.com")
    discard execCmdEx("git -C " & tmp & " config user.name Test")
    discard execCmdEx("git -C " & tmp & " commit --allow-empty -m initial")
    # Create a fake remote and set origin/HEAD.
    discard execCmdEx("git -C " & tmp & " remote add origin " & tmp)
    discard execCmdEx("git -C " & tmp & " fetch origin")
    discard execCmdEx("git -C " & tmp & " remote set-head origin main")
    check resolveDefaultBranch(tmp) == "main"
