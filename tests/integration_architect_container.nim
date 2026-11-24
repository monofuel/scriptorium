import
  std/[json, os, strutils, sysrand, tempfiles],
  acport, jsony,
  scriptorium/[config, git_ops, init, lock_management]

const
  TurnTimeoutMs = 180_000
  SetupTimeoutMs = 60_000

var
  updates: Channel[string]

proc collectUpdate(update: SessionUpdate, userData: pointer) {.gcsafe.} =
  ## Transfer the real bridge's typed updates to the test's owning thread.
  updates.send($update.toJsonNode())

proc main() =
  ## Qualify real file tools and final-answer delivery in an owner-provisioned disposable container.
  let arguments = commandLineParams()
  if arguments.len != 4:
    raise newException(ValueError,
      "Expected disposable-container, shared-fixture-root, project-config, and container-scriptorium arguments")
  let
    container = arguments[0]
    fixtureRoot = absolutePath(arguments[1])
    configPath = absolutePath(arguments[2])
    executable = arguments[3]
    repo = createTempDir("architect-real-read-", "", fixtureRoot)
  defer: removeDir(repo)
  let initialized = runCommandCapture(repo, "git", @["init", "-q", "--initial-branch=master"])
  doAssert initialized.exitCode == 0, initialized.output
  gitRun(repo, "config", "user.name", "Scriptorium synthetic acceptance")
  gitRun(repo, "config", "user.email", "synthetic@localhost")
  writeFile(repo / "AGENTS.md", "# Synthetic acceptance\nRead-only tool and final-answer test; do not modify files.\n")
  writeFile(repo / "Makefile", "test integration-test:\n\t@true\n")
  gitRun(repo, "add", "AGENTS.md", "Makefile")
  gitRun(repo, "commit", "-q", "-m", "synthetic initial state")
  runInit(repo, quiet = true)
  writeFile(repo / "scriptorium.json", readFile(configPath))
  let cfg = loadConfig(repo)
  doAssert cfg.agents.architect.acpAgent == "codex"
  doAssert cfg.agents.architect.model == "gpt-6.1-sol"
  doAssert cfg.agents.architect.reasoningEffort == "high"
  discard withLockedPlanWorktree(repo, proc(plan: string): bool =
    ## Install only synthetic planning state, without importing or touching the human project.
    writeFile(plan / "spec.md", "# Synthetic spec\nThis fixture tests a read-only conversation, not emulator features.\n")
    gitRun(plan, "add", "spec.md")
    gitRun(plan, "commit", "-q", "-m", "synthetic spec")
    true)
  var nonce = ""
  for value in urandom(16): nonce.add(toHex(value.int, 2))
  let
    sample = repo / "sample.txt"
    expected = "READ_OK " & nonce
    before = gitRunCapture(repo, @["rev-parse", "scriptorium/plan"]).output
  writeFile(sample, nonce & "\n")
  gitRun(repo, "add", "sample.txt")
  gitRun(repo, "commit", "-q", "-m", "synthetic file-only nonce")
  updates.open()
  defer: updates.close()
  let client = newAcpClient("scriptorium-container-acceptance", "1",
    ClientHandlers(onUpdate: collectUpdate))
  defer: client.close()
  client.connect("docker", @["exec", "--interactive", "--workdir", repo,
    container, executable, "architect-acp"], workingDir = repo)
  discard client.initialize(SetupTimeoutMs)
  let session = client.newSession(repo, @[], SetupTimeoutMs)
  defer: session.closeSession(SetupTimeoutMs)
  session.setMode("ask", SetupTimeoutMs)
  let answer = session.prompt(@[textBlock(
    "This is a finite synthetic read-only acceptance test. Use the scriptorium-project MCP " &
    "read_project_file tool with path sample.txt to read " & sample &
    ". Then give a final answer consisting of READ_OK followed by a space and the file contents. " &
    "Do not change files, create tickets, use other agents, or run an implementation campaign.")], TurnTimeoutMs)
  doAssert answer.stopReason == endTurn
  var
    completedTool = false
    finalText = ""
    eventCount = 0
  while true:
    let (received, text) = updates.tryRecv()
    if not received: break
    inc eventCount
    let update = parseUpdate(parseJson(text))
    case update.kind
    of toolCall, toolCallUpdate:
      finalText.setLen(0)
      if update.tool.status == "completed": completedTool = true
    of agentMessageChunk:
      if update.content.kind == textContent: finalText.add(update.content.text)
    else: discard
  doAssert completedTool, "No successful native tool operation was observed"
  doAssert expected in finalText, "No final answer with the file-only nonce followed the tool operation"
  doAssert readFile(sample) == nonce & "\n"
  doAssert gitRunCapture(repo, @["rev-parse", "scriptorium/plan"]).output == before
  doAssert not fileExists(repo / ".scriptorium" / "orchestrator.pid")
  let tickets = gitRunCapture(repo, @["ls-tree", "-r", "--name-only", "scriptorium/plan", "tickets"])
  for path in tickets.output.splitLines(): doAssert not path.endsWith(".md")
  echo $(%*{"readToolCompleted": completedTool, "finalAnswerVerified": true,
    "eventCount": eventCount, "model": cfg.agents.architect.model,
    "reasoningEffort": cfg.agents.architect.reasoningEffort,
    "planUnchanged": true, "orchestratorStarted": false})

when isMainModule:
  main()
