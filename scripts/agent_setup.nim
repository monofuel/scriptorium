import
  std/[os, osproc, strtabs]

proc run(command: string, args: seq[string], environment: StringTableRef = nil) =
  ## Run a pinned tool installer and propagate its actual exit status.
  let process = startProcess(command, args = args, env = environment,
    options = {poUsePath, poParentStreams})
  let code = process.waitForExit()
  process.close()
  if code != 0: quit(code)

proc main() =
  ## Materialize locked native executables without changing user installations.
  let root = getCurrentDir() / ".build" / "agent-tools"
  createDir(root)
  copyFile("package.json", root / "package.json")
  copyFile("package-lock.json", root / "package-lock.json")
  run("npm", @["ci", "--ignore-scripts", "--prefix", root])
  run("node", @[root / "node_modules" / "@anthropic-ai" / "claude-code" / "install.cjs"])
  let environment = newStringTable(modeCaseSensitive)
  for key, value in envPairs(): environment[key] = value
  environment["GROK_HOME"] = root / "grok-home"
  environment["npm_config_user_agent"] = "npm/scriptorium"
  run("node", @[root / "node_modules" / "@xai-official" / "grok" / "bin" / "postinstall.js"], environment)
  for name in ["codex", "claude", "grok", "codex-acp", "claude-agent-acp"]:
    run(root / "node_modules" / ".bin" / name, @["--version"])

main()
