import
  std/[os, strutils],
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
  doAssert cfg.discord.allowedUsers.len == 0
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
      "coding": {"model": "custom-code", "hardTimeout": 5000, "noOutputTimeout": 6000, "progressTimeout": 7000},
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
    "discord": {"serverId": "srv-1", "channelId": "12345", "allowedUsers": ["alice", "bob"]},
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
  doAssert cfg.agents.coding.hardTimeout == 5000
  doAssert cfg.agents.coding.noOutputTimeout == 6000
  doAssert cfg.agents.coding.progressTimeout == 7000
  doAssert cfg.loop.enabled == true
  doAssert cfg.loop.feedback == "echo ok"
  doAssert cfg.loop.goal == "ship it"
  doAssert cfg.loop.maxIterations == 5
  doAssert cfg.discord.serverId == "srv-1"
  doAssert cfg.discord.channelId == "12345"
  doAssert cfg.discord.allowedUsers == @["alice", "bob"]
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

  let json = """{"discord": {"serverId": "srv-42", "channelId": "ch-999", "allowedUsers": ["user1", "user2", "user3"]}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let cfg = loadConfig(tmpDir)
  doAssert cfg.discord.serverId == "srv-42"
  doAssert cfg.discord.channelId == "ch-999"
  doAssert cfg.discord.allowedUsers == @["user1", "user2", "user3"]
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
  doAssert cfg.mattermost.allowedUsers.len == 0
  echo "[OK] defaultConfig returns expected mattermost defaults"

proc testMattermostConfigLoading() =
  ## Verify mattermost section fields are loaded correctly from JSON.
  let tmpDir = getTempDir() / "test_config_mattermost"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"mattermost": {"url": "https://mm.example.com", "channelId": "ch-abc", "allowedUsers": ["u1", "u2"]}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let cfg = loadConfig(tmpDir)
  doAssert cfg.mattermost.url == "https://mm.example.com"
  doAssert cfg.mattermost.channelId == "ch-abc"
  doAssert cfg.mattermost.allowedUsers == @["u1", "u2"]
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
  doAssert cfg.mattermost.allowedUsers.len == 0
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

proc testPerAgentTimeoutDefaults() =
  ## Verify defaultConfig sets per-agent timeout fields to expected role-specific defaults.
  let cfg = defaultConfig()
  doAssert cfg.agents.architect.hardTimeout == 7_200_000
  doAssert cfg.agents.architect.noOutputTimeout == 600_000
  doAssert cfg.agents.architect.progressTimeout == 0

  doAssert cfg.agents.coding.hardTimeout == 14_400_000
  doAssert cfg.agents.coding.noOutputTimeout == 300_000
  doAssert cfg.agents.coding.progressTimeout == 600_000

  doAssert cfg.agents.manager.hardTimeout == 3_600_000
  doAssert cfg.agents.manager.noOutputTimeout == 300_000
  doAssert cfg.agents.manager.progressTimeout == 0

  doAssert cfg.agents.reviewer.hardTimeout == 3_600_000
  doAssert cfg.agents.reviewer.noOutputTimeout == 300_000
  doAssert cfg.agents.reviewer.progressTimeout == 0

  doAssert cfg.agents.audit.hardTimeout == 0
  doAssert cfg.agents.audit.noOutputTimeout == 0
  doAssert cfg.agents.audit.progressTimeout == 0
  echo "[OK] per-agent timeout defaults are correct for all roles"

proc testPerAgentTimeoutOverride() =
  ## Verify a partial config overrides one agent timeout while others keep defaults.
  let tmpDir = getTempDir() / "test_config_agent_timeout_override"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"agents": {"coding": {"hardTimeout": 5000}}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let cfg = loadConfig(tmpDir)
  doAssert cfg.agents.coding.hardTimeout == 5000
  doAssert cfg.agents.coding.noOutputTimeout == 300_000
  doAssert cfg.agents.coding.progressTimeout == 600_000
  doAssert cfg.agents.architect.hardTimeout == 7_200_000
  doAssert cfg.agents.manager.hardTimeout == 3_600_000
  doAssert cfg.agents.reviewer.hardTimeout == 3_600_000
  echo "[OK] per-agent timeout override works for single field"

proc testPerAgentTimeoutFullOverride() =
  ## Verify all three timeout fields load correctly when set on architect.
  let tmpDir = getTempDir() / "test_config_agent_timeout_full"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"agents": {"architect": {"hardTimeout": 1000, "noOutputTimeout": 2000, "progressTimeout": 3000}}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let cfg = loadConfig(tmpDir)
  doAssert cfg.agents.architect.hardTimeout == 1000
  doAssert cfg.agents.architect.noOutputTimeout == 2000
  doAssert cfg.agents.architect.progressTimeout == 3000
  doAssert cfg.agents.coding.hardTimeout == 14_400_000
  echo "[OK] per-agent timeout full override on architect works correctly"

proc testExplicitZeroTimeoutOverrides() =
  ## Verify that explicit zero-value timeouts in JSON override non-zero defaults.
  ## With deep merge, any key present in user JSON is treated as intentional.
  let tmpDir = getTempDir() / "test_config_zero_timeout"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"agents": {"coding": {"hardTimeout": 0, "noOutputTimeout": 0, "progressTimeout": 0}}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let cfg = loadConfig(tmpDir)
  doAssert cfg.agents.coding.hardTimeout == 0
  doAssert cfg.agents.coding.noOutputTimeout == 0
  doAssert cfg.agents.coding.progressTimeout == 0
  echo "[OK] explicit zero-value timeouts override defaults"

proc testNormalizeConfigWriteBack() =
  ## Verify normalizeConfig writes back pretty-printed JSON with all defaults filled in.
  let tmpDir = getTempDir() / "test_config_writeback"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"agents": {"architect": {"model": "claude-sonnet-4-6"}}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  normalizeConfig(tmpDir)

  let written = readFile(tmpDir / "scriptorium.json")
  # Pretty-printed: contains newlines and indentation.
  doAssert "\n" in written
  doAssert "  " in written
  # New default fields appear.
  doAssert "maxAgents" in written
  doAssert "dashboard" in written
  doAssert "devops" in written
  # User value preserved.
  doAssert "claude-sonnet-4-6" in written
  echo "[OK] normalizeConfig writes back pretty-printed JSON with all defaults"

proc testNormalizeConfigStripsUnknownKeys() =
  ## Verify unknown keys are stripped by normalizeConfig.
  let tmpDir = getTempDir() / "test_config_strip_unknown"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"agents": {"architect": {"model": "claude-opus-4-6"}}, "bogusKey": "should-be-removed", "anotherUnknown": 42}"""
  writeFile(tmpDir / "scriptorium.json", json)

  normalizeConfig(tmpDir)

  let written = readFile(tmpDir / "scriptorium.json")
  doAssert "bogusKey" notin written
  doAssert "anotherUnknown" notin written
  doAssert "should-be-removed" notin written
  echo "[OK] unknown keys stripped by normalizeConfig"

proc testLoadConfigIsReadOnly() =
  ## Verify loadConfig does not modify the file on disk.
  let tmpDir = getTempDir() / "test_config_readonly"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"agents": {"architect": {"model": "claude-sonnet-4-6"}}}"""
  let configPath = tmpDir / "scriptorium.json"
  writeFile(configPath, json)

  discard loadConfig(tmpDir)

  let afterLoad = readFile(configPath)
  doAssert afterLoad == json
  echo "[OK] loadConfig does not modify the file on disk"

proc testDiscordEnabledField() =
  ## Verify discord enabled field defaults to false and loads true from JSON.
  let cfg = defaultConfig()
  doAssert cfg.discord.enabled == false

  let tmpDir = getTempDir() / "test_config_discord_enabled"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"discord": {"enabled": true}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let loaded = loadConfig(tmpDir)
  doAssert loaded.discord.enabled == true
  echo "[OK] discord enabled field defaults to false and loads true"

proc testMattermostEnabledField() =
  ## Verify mattermost enabled field defaults to false and loads true from JSON.
  let cfg = defaultConfig()
  doAssert cfg.mattermost.enabled == false

  let tmpDir = getTempDir() / "test_config_mattermost_enabled"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"mattermost": {"enabled": true}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let loaded = loadConfig(tmpDir)
  doAssert loaded.mattermost.enabled == true
  echo "[OK] mattermost enabled field defaults to false and loads true"

proc testApplyLogLevelFromConfig() =
  ## Verify applyLogLevelFromConfig sets log levels from config file.
  let tmpDir = getTempDir() / "test_apply_log_level"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"logLevel": "debug", "fileLogLevel": "warn"}"""
  writeFile(tmpDir / "scriptorium.json", json)

  # Reset to defaults before testing.
  setLogLevel(lvlInfo)
  setFileLogLevel(lvlDebug)

  applyLogLevelFromConfig(tmpDir)
  doAssert minLogLevel == lvlDebug
  doAssert minFileLogLevel == lvlWarn

  # Restore defaults.
  setLogLevel(lvlInfo)
  setFileLogLevel(lvlDebug)
  echo "[OK] applyLogLevelFromConfig sets levels from config"

proc testChatHistoryCountConfig() =
  ## Verify chatHistoryCount defaults and custom JSON loading for discord and mattermost.
  let cfg = defaultConfig()
  doAssert cfg.discord.chatHistoryCount == 8
  doAssert cfg.mattermost.chatHistoryCount == 8

  let tmpDir = getTempDir() / "test_config_chat_history"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"discord": {"chatHistoryCount": 20}, "mattermost": {"chatHistoryCount": 15}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let loaded = loadConfig(tmpDir)
  doAssert loaded.discord.chatHistoryCount == 20
  doAssert loaded.mattermost.chatHistoryCount == 15
  echo "[OK] chatHistoryCount defaults and custom values load correctly"

proc testSaveConfigRoundTrip() =
  ## Verify saveConfig followed by loadConfig preserves all field values.
  let tmpDir = getTempDir() / "test_config_save_round_trip"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let original = defaultConfig()
  saveConfig(tmpDir, original)
  let loaded = loadConfig(tmpDir)

  # Agents.
  doAssert loaded.agents.architect.model == original.agents.architect.model
  doAssert loaded.agents.architect.harness == original.agents.architect.harness
  doAssert loaded.agents.architect.hardTimeout == original.agents.architect.hardTimeout
  doAssert loaded.agents.architect.noOutputTimeout == original.agents.architect.noOutputTimeout
  doAssert loaded.agents.architect.progressTimeout == original.agents.architect.progressTimeout
  doAssert loaded.agents.coding.model == original.agents.coding.model
  doAssert loaded.agents.coding.harness == original.agents.coding.harness
  doAssert loaded.agents.coding.hardTimeout == original.agents.coding.hardTimeout
  doAssert loaded.agents.coding.noOutputTimeout == original.agents.coding.noOutputTimeout
  doAssert loaded.agents.coding.progressTimeout == original.agents.coding.progressTimeout
  doAssert loaded.agents.manager.model == original.agents.manager.model
  doAssert loaded.agents.reviewer.model == original.agents.reviewer.model
  doAssert loaded.agents.audit.model == original.agents.audit.model

  # Endpoints.
  doAssert loaded.endpoints.local == original.endpoints.local

  # Concurrency.
  doAssert loaded.concurrency.maxAgents == original.concurrency.maxAgents
  doAssert loaded.concurrency.tokenBudgetMB == original.concurrency.tokenBudgetMB

  # Timeouts.
  doAssert loaded.timeouts.codingAgentHardTimeoutMs == original.timeouts.codingAgentHardTimeoutMs
  doAssert loaded.timeouts.codingAgentNoOutputTimeoutMs == original.timeouts.codingAgentNoOutputTimeoutMs
  doAssert loaded.timeouts.codingAgentProgressTimeoutMs == original.timeouts.codingAgentProgressTimeoutMs
  doAssert loaded.timeouts.codingAgentMaxAttempts == original.timeouts.codingAgentMaxAttempts

  # Loop.
  doAssert loaded.loop.enabled == original.loop.enabled
  doAssert loaded.loop.feedback == original.loop.feedback
  doAssert loaded.loop.goal == original.loop.goal
  doAssert loaded.loop.maxIterations == original.loop.maxIterations
  doAssert loaded.loop.feedbackTimeoutMs == original.loop.feedbackTimeoutMs

  # Discord.
  doAssert loaded.discord.enabled == original.discord.enabled
  doAssert loaded.discord.serverId == original.discord.serverId
  doAssert loaded.discord.channelId == original.discord.channelId
  doAssert loaded.discord.allowedUsers == original.discord.allowedUsers
  doAssert loaded.discord.chatHistoryCount == original.discord.chatHistoryCount

  # Mattermost.
  doAssert loaded.mattermost.enabled == original.mattermost.enabled
  doAssert loaded.mattermost.url == original.mattermost.url
  doAssert loaded.mattermost.channelId == original.mattermost.channelId
  doAssert loaded.mattermost.allowedUsers == original.mattermost.allowedUsers
  doAssert loaded.mattermost.chatHistoryCount == original.mattermost.chatHistoryCount

  # Dashboard.
  doAssert loaded.dashboard.port == original.dashboard.port
  doAssert loaded.dashboard.host == original.dashboard.host

  # Devops.
  doAssert loaded.devops.enabled == original.devops.enabled

  # Remote sync.
  doAssert loaded.remoteSync.enabled == original.remoteSync.enabled
  doAssert loaded.remoteSync.primaryRemote == original.remoteSync.primaryRemote
  doAssert loaded.remoteSync.remotes == original.remoteSync.remotes
  doAssert loaded.remoteSync.syncIntervalSeconds == original.remoteSync.syncIntervalSeconds

  # Top-level fields.
  doAssert loaded.logLevel == original.logLevel
  doAssert loaded.fileLogLevel == original.fileLogLevel
  doAssert loaded.syncAgentsMd == original.syncAgentsMd
  echo "[OK] saveConfig round-trip preserves all field values"

proc testLoopFeedbackTimeoutConfig() =
  ## Verify feedbackTimeoutMs default and custom JSON loading for loop config.
  let cfg = defaultConfig()
  doAssert cfg.loop.feedbackTimeoutMs == DefaultFeedbackTimeoutMs

  let tmpDir = getTempDir() / "test_config_feedback_timeout"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let json = """{"loop": {"feedbackTimeoutMs": 30000}}"""
  writeFile(tmpDir / "scriptorium.json", json)

  let loaded = loadConfig(tmpDir)
  doAssert loaded.loop.feedbackTimeoutMs == 30000
  echo "[OK] feedbackTimeoutMs default and custom value load correctly"

proc testCorruptedJsonRaisesValueError() =
  ## Verify loadConfig raises ValueError with clear message on corrupted JSON.
  let tmpDir = getTempDir() / "test_config_corrupted_json"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  writeFile(tmpDir / "scriptorium.json", "{not valid json!!!")

  var raised = false
  try:
    discard loadConfig(tmpDir)
  except ValueError:
    raised = true
    let msg = getCurrentExceptionMsg()
    doAssert "scriptorium.json is corrupted or not valid JSON" in msg
    doAssert "scriptorium init" in msg
  doAssert raised, "loadConfig should raise ValueError on corrupted JSON"
  echo "[OK] corrupted JSON raises ValueError with clear recovery message"

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
  testPerAgentTimeoutDefaults()
  testPerAgentTimeoutOverride()
  testPerAgentTimeoutFullOverride()
  testExplicitZeroTimeoutOverrides()
  testNormalizeConfigWriteBack()
  testNormalizeConfigStripsUnknownKeys()
  testLoadConfigIsReadOnly()
  testDiscordEnabledField()
  testMattermostEnabledField()
  testApplyLogLevelFromConfig()
  testChatHistoryCountConfig()
  testLoopFeedbackTimeoutConfig()
  testSaveConfigRoundTrip()
  testCorruptedJsonRaisesValueError()
