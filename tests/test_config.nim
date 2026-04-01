import
  std/[os],
  scriptorium/[config, logging]

proc testDefaultConfigValues() =
  ## Verify defaultConfig returns expected default values for all fields.
  let cfg = defaultConfig()
  doAssert cfg.agents.architect.model == "claude-opus-4-6"
  doAssert cfg.agents.coding.model == "claude-sonnet-4-6"
  doAssert cfg.agents.manager.model == "claude-sonnet-4-6"
  doAssert cfg.agents.reviewer.model == "claude-sonnet-4-6"
  doAssert cfg.agents.audit.model == "claude-haiku-4-5-20251001"
  doAssert cfg.agents.architect.harness == harnessClaudeCode
  doAssert cfg.agents.coding.harness == harnessClaudeCode
  doAssert cfg.endpoints.local == "http://127.0.0.1:8097"
  doAssert cfg.concurrency.maxAgents == 4
  doAssert cfg.concurrency.tokenBudgetMB == 0
  doAssert cfg.loop.enabled == false
  doAssert cfg.discord.serverId == ""
  doAssert cfg.discord.channelId == ""
  doAssert cfg.discord.allowedUserIds.len == 0
  doAssert cfg.dashboard.port == 8098
  doAssert cfg.dashboard.host == "127.0.0.1"
  doAssert cfg.logLevel == ""
  doAssert cfg.fileLogLevel == ""
  echo "[OK] defaultConfig returns expected default values"

proc testMissingConfigFile() =
  ## Verify loadConfig returns defaults when no scriptorium.json exists.
  let tmpDir = getTempDir() / "test_config_missing"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let cfg = loadConfig(tmpDir)
  let def = defaultConfig()
  doAssert cfg.agents.architect.model == def.agents.architect.model
  doAssert cfg.concurrency.maxAgents == def.concurrency.maxAgents
  doAssert cfg.loop.enabled == def.loop.enabled
  echo "[OK] loadConfig returns defaults when config file is missing"

proc testPartialJsonMerge() =
  ## Verify partial JSON overrides only the specified field, keeping other defaults.
  let tmpDir = getTempDir() / "test_config_partial"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"agents": {"coding": {"model": "custom-model"}}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let cfg = loadConfig(tmpDir)
  doAssert cfg.agents.coding.model == "custom-model"
  doAssert cfg.agents.coding.harness == harnessTypoi  # inferHarness("custom-model")
  doAssert cfg.agents.architect.model == "claude-opus-4-6"
  doAssert cfg.concurrency.maxAgents == 4
  echo "[OK] partial JSON overrides only specified field"

proc testFullJsonMerge() =
  ## Verify all sections are loaded when a full config JSON is provided.
  let tmpDir = getTempDir() / "test_config_full"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{
    "agents": {
      "architect": {"model": "custom-arch", "harness": "codex"},
      "coding": {"model": "custom-code"},
      "manager": {"model": "custom-mgr"},
      "reviewer": {"model": "custom-rev"},
      "audit": {"model": "custom-audit"}
    },
    "endpoints": {"local": "http://localhost:9999"},
    "concurrency": {"maxAgents": 8, "tokenBudgetMB": 100},
    "timeouts": {
      "codingAgentHardTimeoutMs": 1000,
      "codingAgentNoOutputTimeoutMs": 2000,
      "codingAgentProgressTimeoutMs": 3000,
      "codingAgentMaxAttempts": 10
    },
    "loop": {"enabled": true, "feedback": "echo ok", "goal": "ship it", "maxIterations": 5},
    "discord": {"serverId": "srv-1", "channelId": "12345", "allowedUserIds": ["alice", "bob"]},
    "dashboard": {"port": 9999, "host": "0.0.0.0"}
  }"""
  writeFile(tmpDir / "scriptorium.json", json)

  let cfg = loadConfig(tmpDir)
  doAssert cfg.agents.architect.model == "custom-arch"
  doAssert cfg.agents.architect.harness == harnessCodex
  doAssert cfg.agents.coding.model == "custom-code"
  doAssert cfg.agents.manager.model == "custom-mgr"
  doAssert cfg.agents.reviewer.model == "custom-rev"
  doAssert cfg.agents.audit.model == "custom-audit"
  doAssert cfg.endpoints.local == "http://localhost:9999"
  doAssert cfg.concurrency.maxAgents == 8
  doAssert cfg.concurrency.tokenBudgetMB == 100
  doAssert cfg.timeouts.codingAgentHardTimeoutMs == 1000
  doAssert cfg.timeouts.codingAgentNoOutputTimeoutMs == 2000
  doAssert cfg.timeouts.codingAgentProgressTimeoutMs == 3000
  doAssert cfg.timeouts.codingAgentMaxAttempts == 10
  doAssert cfg.loop.enabled == true
  doAssert cfg.loop.feedback == "echo ok"
  doAssert cfg.loop.goal == "ship it"
  doAssert cfg.loop.maxIterations == 5
  doAssert cfg.discord.serverId == "srv-1"
  doAssert cfg.discord.channelId == "12345"
  doAssert cfg.discord.allowedUserIds == @["alice", "bob"]
  doAssert cfg.dashboard.port == 9999
  doAssert cfg.dashboard.host == "0.0.0.0"
  echo "[OK] full JSON merge loads all values correctly"

proc testEnvVarOverrideLogLevel() =
  ## Verify SCRIPTORIUM_LOG_LEVEL env var overrides config file logLevel.
  let tmpDir = getTempDir() / "test_config_env_log"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"logLevel": "info"}"""
  writeFile(tmpDir / "scriptorium.json", json)

  putEnv("SCRIPTORIUM_LOG_LEVEL", "debug")
  defer: delEnv("SCRIPTORIUM_LOG_LEVEL")

  let cfg = loadConfig(tmpDir)
  doAssert cfg.logLevel == "debug"
  echo "[OK] SCRIPTORIUM_LOG_LEVEL env var overrides config logLevel"

proc testEnvVarOverrideFileLogLevel() =
  ## Verify SCRIPTORIUM_FILE_LOG_LEVEL env var overrides config file fileLogLevel.
  let tmpDir = getTempDir() / "test_config_env_filelog"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"fileLogLevel": "warn"}"""
  writeFile(tmpDir / "scriptorium.json", json)

  putEnv("SCRIPTORIUM_FILE_LOG_LEVEL", "trace")
  defer: delEnv("SCRIPTORIUM_FILE_LOG_LEVEL")

  let cfg = loadConfig(tmpDir)
  doAssert cfg.fileLogLevel == "trace"
  echo "[OK] SCRIPTORIUM_FILE_LOG_LEVEL env var overrides config fileLogLevel"

proc testDiscordConfigLoading() =
  ## Verify discord section fields are loaded correctly from JSON.
  let tmpDir = getTempDir() / "test_config_discord"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"discord": {"serverId": "srv-42", "channelId": "ch-999", "allowedUserIds": ["user1", "user2", "user3"]}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let cfg = loadConfig(tmpDir)
  doAssert cfg.discord.serverId == "srv-42"
  doAssert cfg.discord.channelId == "ch-999"
  doAssert cfg.discord.allowedUserIds == @["user1", "user2", "user3"]
  echo "[OK] discord config fields loaded correctly"

proc testDiscordTokenPresent() =
  ## Verify discordTokenPresent returns correct boolean based on DISCORD_TOKEN env var.
  let saved = getEnv("DISCORD_TOKEN")
  defer:
    if saved.len > 0:
      putEnv("DISCORD_TOKEN", saved)
    else:
      delEnv("DISCORD_TOKEN")

  delEnv("DISCORD_TOKEN")
  doAssert discordTokenPresent() == false

  putEnv("DISCORD_TOKEN", "some-token")
  doAssert discordTokenPresent() == true

  delEnv("DISCORD_TOKEN")
  doAssert discordTokenPresent() == false
  echo "[OK] discordTokenPresent reflects DISCORD_TOKEN env var"

proc testResolveModel() =
  ## Verify resolveModel translates model IDs when CLAUDE_CODE_USE_BEDROCK is set and passes through otherwise.
  let saved = getEnv("CLAUDE_CODE_USE_BEDROCK")
  defer:
    if saved.len > 0:
      putEnv("CLAUDE_CODE_USE_BEDROCK", saved)
    else:
      delEnv("CLAUDE_CODE_USE_BEDROCK")

  # Without bedrock, model passes through unchanged.
  delEnv("CLAUDE_CODE_USE_BEDROCK")
  doAssert resolveModel("claude-opus-4-6") == "claude-opus-4-6"
  doAssert resolveModel("claude-sonnet-4-6") == "claude-sonnet-4-6"
  doAssert resolveModel("some-other-model") == "some-other-model"

  # With bedrock, claude models are translated.
  putEnv("CLAUDE_CODE_USE_BEDROCK", "1")
  doAssert resolveModel("claude-opus-4-6") == "us.anthropic.claude-opus-4-6-v1"
  doAssert resolveModel("claude-sonnet-4-6") == "us.anthropic.claude-sonnet-4-6"
  doAssert resolveModel("claude-haiku-4-5-20251001") == "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  doAssert resolveModel("some-other-model") == "some-other-model"
  echo "[OK] resolveModel translates correctly with and without CLAUDE_CODE_USE_BEDROCK"

proc testDashboardConfigLoading() =
  ## Verify dashboard section fields are loaded correctly from JSON.
  let tmpDir = getTempDir() / "test_config_dashboard"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"dashboard": {"port": 9000, "host": "0.0.0.0"}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let cfg = loadConfig(tmpDir)
  doAssert cfg.dashboard.port == 9000
  doAssert cfg.dashboard.host == "0.0.0.0"
  doAssert cfg.agents.architect.model == "claude-opus-4-6"
  doAssert cfg.concurrency.maxAgents == 4
  echo "[OK] dashboard config fields loaded correctly"

proc testDashboardPartialConfig() =
  ## Verify partial dashboard JSON overrides only port while host stays default.
  let tmpDir = getTempDir() / "test_config_dashboard_partial"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"dashboard": {"port": 9000}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let cfg = loadConfig(tmpDir)
  doAssert cfg.dashboard.port == 9000
  doAssert cfg.dashboard.host == "127.0.0.1"
  echo "[OK] dashboard partial config works correctly"

proc testDefaultMattermostConfig() =
  ## Verify defaultConfig returns expected default values for mattermost fields.
  let cfg = defaultConfig()
  doAssert cfg.mattermost.url == ""
  doAssert cfg.mattermost.channelId == ""
  doAssert cfg.mattermost.allowedUserIds.len == 0
  echo "[OK] defaultConfig returns expected mattermost defaults"

proc testMattermostConfigLoading() =
  ## Verify mattermost section fields are loaded correctly from JSON.
  let tmpDir = getTempDir() / "test_config_mattermost"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"mattermost": {"url": "https://mm.example.com", "channelId": "ch-abc", "allowedUserIds": ["u1", "u2"]}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let cfg = loadConfig(tmpDir)
  doAssert cfg.mattermost.url == "https://mm.example.com"
  doAssert cfg.mattermost.channelId == "ch-abc"
  doAssert cfg.mattermost.allowedUserIds == @["u1", "u2"]
  echo "[OK] mattermost config fields loaded correctly"

proc testMattermostPartialConfig() =
  ## Verify partial mattermost JSON only overrides specified fields.
  let tmpDir = getTempDir() / "test_config_mattermost_partial"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"mattermost": {"url": "https://mm.example.com"}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let cfg = loadConfig(tmpDir)
  doAssert cfg.mattermost.url == "https://mm.example.com"
  doAssert cfg.mattermost.channelId == ""
  doAssert cfg.mattermost.allowedUserIds.len == 0
  echo "[OK] mattermost partial config works correctly"

proc testMattermostTokenPresent() =
  ## Verify mattermostTokenPresent returns correct boolean based on MATTERMOST_TOKEN env var.
  let saved = getEnv("MATTERMOST_TOKEN")
  defer:
    if saved.len > 0:
      putEnv("MATTERMOST_TOKEN", saved)
    else:
      delEnv("MATTERMOST_TOKEN")

  delEnv("MATTERMOST_TOKEN")
  doAssert mattermostTokenPresent() == false

  putEnv("MATTERMOST_TOKEN", "some-token")
  doAssert mattermostTokenPresent() == true

  delEnv("MATTERMOST_TOKEN")
  doAssert mattermostTokenPresent() == false
  echo "[OK] mattermostTokenPresent reflects MATTERMOST_TOKEN env var"

proc testInferHarness() =
  ## Verify inferHarness maps model prefixes to correct harnesses.
  doAssert inferHarness("claude-sonnet-4-6") == harnessClaudeCode
  doAssert inferHarness("claude-opus-4-6") == harnessClaudeCode
  doAssert inferHarness("codex-mini") == harnessCodex
  doAssert inferHarness("gpt-4o") == harnessCodex
  doAssert inferHarness("some-random-model") == harnessTypoi
  doAssert inferHarness("llama-3") == harnessTypoi
  echo "[OK] inferHarness maps model prefixes to correct harnesses"

proc testParseLogLevel() =
  ## Verify parseLogLevel maps strings to correct LogLevel values.
  doAssert parseLogLevel("debug") == lvlDebug
  doAssert parseLogLevel("info") == lvlInfo
  doAssert parseLogLevel("warn") == lvlWarn
  doAssert parseLogLevel("warning") == lvlWarn
  doAssert parseLogLevel("error") == lvlError
  doAssert parseLogLevel("DEBUG") == lvlDebug
  var raised = false
  try:
    discard parseLogLevel("invalid")
  except ValueError:
    raised = true
  doAssert raised, "parseLogLevel should raise ValueError for invalid input"
  echo "[OK] parseLogLevel maps strings correctly"

when isMainModule:
  testParseLogLevel()
  testDefaultConfigValues()
  testMissingConfigFile()
  testPartialJsonMerge()
  testFullJsonMerge()
  testEnvVarOverrideLogLevel()
  testEnvVarOverrideFileLogLevel()
  testDiscordConfigLoading()
  testDiscordTokenPresent()
  testResolveModel()
  testInferHarness()
  testDashboardConfigLoading()
  testDashboardPartialConfig()
  testDefaultMattermostConfig()
  testMattermostConfigLoading()
  testMattermostPartialConfig()
  testMattermostTokenPresent()
