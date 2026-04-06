import
  std/[os, strutils],
  jsony,
  scriptorium/[config, prompt_builders]

proc testDevopsConfigDefault() =
  ## Verify devops is disabled by default.
  let cfg = defaultConfig()
  doAssert cfg.devops.enabled == false
  echo "[OK] devops disabled by default"

proc testDevopsConfigFromJson() =
  ## Verify devops.enabled can be loaded from JSON.
  let tmpDir = getTempDir() / "test_devops_config"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  writeFile(tmpDir / "scriptorium.json", """{"devops": {"enabled": true}}""")
  let cfg = loadConfig(tmpDir)
  doAssert cfg.devops.enabled == true
  echo "[OK] devops.enabled loaded from JSON"

proc testDevopsConfigDisabledFromJson() =
  ## Verify devops.enabled=false from JSON.
  let tmpDir = getTempDir() / "test_devops_config_off"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  writeFile(tmpDir / "scriptorium.json", """{"devops": {"enabled": false}}""")
  let cfg = loadConfig(tmpDir)
  doAssert cfg.devops.enabled == false
  echo "[OK] devops.enabled=false from JSON"

proc testWithDevopsEnabled() =
  ## Verify withDevops appends guidance when enabled.
  let base = "base prompt"
  let result = withDevops(base, true)
  doAssert "Devops Context" in result
  doAssert "services/" in result.toLowerAscii() or "Services" in result
  doAssert base in result
  echo "[OK] withDevops appends guidance when enabled"

proc testWithDevopsDisabled() =
  ## Verify withDevops passes through when disabled.
  let base = "base prompt"
  let result = withDevops(base, false)
  doAssert result == base
  echo "[OK] withDevops passes through when disabled"

when isMainModule:
  testDevopsConfigDefault()
  testDevopsConfigFromJson()
  testDevopsConfigDisabledFromJson()
  testWithDevopsEnabled()
  testWithDevopsDisabled()
