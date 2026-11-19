## Drive the real `scriptorium architect-acp` command over stdio with a scripted Architect agent.

import
  std/[base64, json, options, os, osproc, posix, strutils, tables, tempfiles, unittest],
  acport, crunchy, jsony,
  scriptorium/[config, git_ops, init, pause_flag]

const
  TimeoutMs = 60_000
  PollMs = 25
  CleanupWaitMs = 10_000
  PngPixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
  SecretUrl = "http://127.0.0.1:9/mcp?scope=secret-scope"
  SecretHeader = "Bearer secret-token"
  SecretInstructions = "Guildhall secret instructions"
  ContextMarker = "Context from Scriptorium"

let
  root = currentSourcePath().parentDir.parentDir
  compiler = getEnv("NIM", "nim")
  buildRoot = root / ".build" / "test-binaries"
  fixture = buildRoot / "architect-acp-fixture"
  binary = buildRoot / "architect-acp-scriptorium"

var
  updates: Channel[string]
  questions: Channel[string]
  consents: Channel[string]
  completions: Channel[string]
  permissionsAsked: int
  allowPermissions: bool

proc compile(source, output, cache: string) =
  ## Build one executable used by the stdio tests.
  let process = startProcess(compiler, workingDir = root, args = @["c", "--hints:off",
    "--warnings:off", "--nimcache:" & (root / ".build" / "test-cache" / cache),
    "-o:" & output, source], options = {poUsePath, poParentStreams})
  let code = process.waitForExit()
  process.close()
  doAssert code == 0, "Could not compile " & source

createDir(buildRoot)
compile(root / "tests" / "fixtures" / "acp_agent.nim", fixture, "architect-acp-fixture")
compile(root / "src" / "scriptorium.nim", binary, "architect-acp-scriptorium")
updates.open()
questions.open()
consents.open()
completions.open()

proc collectUpdate(update: SessionUpdate, userData: pointer) {.gcsafe.} =
  ## Hand streamed updates to the test thread.
  {.cast(gcsafe).}:
    updates.send($update.toJsonNode())

proc answerPermission(context: RequestContext, request: PermissionRequest,
    userData: pointer): PermissionOutcome {.gcsafe.} =
  ## Answer forwarded permissions according to the current test setting.
  {.cast(gcsafe).}:
    discard atomicInc(permissionsAsked)
    let wanted = if atomicLoadN(addr allowPermissions, ATOMIC_ACQUIRE): "allow_once" else: "reject_once"
    result = PermissionOutcome(outcome: "cancelled")
    for option in request.options:
      if option.kind == wanted: result = PermissionOutcome(outcome: "selected", optionId: option.optionId)

proc answerQuestion(context: RequestContext, request: ElicitationRequest,
    userData: pointer): ElicitationResponse {.gcsafe.} =
  ## Answer a forwarded structured question.
  {.cast(gcsafe).}:
    questions.send($(%*{"sessionId": request.sessionId, "message": request.message}))
    result = ElicitationResponse(action: acceptElicitation, content: %*{"color": "blue"})

proc answerConsent(context: RequestContext, request: ElicitationRequest,
    userData: pointer): ElicitationResponse {.gcsafe.} =
  ## Record a forwarded URL consent request and accept it without opening anything.
  {.cast(gcsafe).}:
    consents.send($request.toJsonNode())
    result = ElicitationResponse(action: acceptElicitation)

proc collectCompletion(completion: ElicitationComplete, userData: pointer) {.gcsafe.} =
  ## Hand URL-flow completions to the test thread.
  {.cast(gcsafe).}:
    completions.send(completion.elicitationId)

proc drainUpdates(): seq[JsonNode] =
  ## Collect every update delivered so far.
  while true:
    let (received, text) = updates.tryRecv()
    if not received: break
    result.add(parseJson(text))

proc messageText(items: seq[JsonNode], kind = "agent_message_chunk"): string =
  ## Concatenate text chunks of one update kind.
  for item in items:
    if item["update"]["sessionUpdate"].getStr() == kind:
      result.add(item["update"]["content"]{"text"}.getStr())

proc fixtureLog(repo: string): seq[JsonNode] =
  ## Read the scripted agent's observations.
  let path = repo / "fixture.log"
  if fileExists(path):
    for line in lines(path): result.add(parseJson(line))

proc lastPromptText(repo: string): string =
  ## Return the text the scripted Architect received in its latest prompt.
  for entry in fixtureLog(repo):
    if entry["method"].getStr() == "session/prompt": result = entry["text"].getStr()

proc imageChunks(items: seq[JsonNode]): seq[JsonNode] =
  ## Select replayed user image blocks.
  for item in items:
    if item["update"]["sessionUpdate"].getStr() == "user_message_chunk" and
        item["update"]["content"]["type"].getStr() == "image":
      result.add(item["update"]["content"])

proc digestHex(data: string): string =
  ## Encode a SHA-256 digest as lowercase hexadecimal.
  for value in sha256(data): result.add(toHex(value.int, 2).toLowerAscii())

proc pngHeader(width, height: int): string =
  ## Build a minimal PNG whose header declares the given dimensions.
  proc be32(value: int): string =
    ## Encode a big-endian 32-bit integer.
    for shift in [24, 16, 8, 0]: result.add(chr((value shr shift) and 0xFF))
  "\x89PNG\r\n\x1A\n" & be32(13) & "IHDR" & be32(width) & be32(height) & "\x08\x02\x00\x00\x00" &
    be32(0) & be32(0) & "IEND\xAE\x42\x60\x82"

proc promptCount(repo: string): int =
  ## Count prompts the scripted Architect actually received.
  for entry in fixtureLog(repo):
    if entry["method"].getStr() == "session/prompt": inc result

proc waitFor(condition: proc(): bool) =
  ## Poll a condition with a generous deadline.
  var waited = 0
  while not condition():
    doAssert waited < TimeoutMs, "condition was not reached"
    sleep(PollMs)
    waited += PollMs

proc makeRepo(): string =
  ## Initialize a disposable repository whose Architect is the scripted agent.
  result = createTempDir("scriptorium-architect-acp-", "")
  discard execCmdEx("git -C " & quoteShell(result) & " init -q")
  discard execCmdEx("git -C " & quoteShell(result) & " -c user.email=t@t -c user.name=T commit -q --allow-empty -m initial")
  writeFile(result / ".git" / "config", readFile(result / ".git" / "config") &
    "\n[user]\n\temail = test@test.com\n\tname = Test\n")
  runInit(result, quiet = true)
  var cfg = loadConfig(result)
  cfg.acpAgents["fixture"] = AcpAgentProfile(command: fixture, readOnlyMode: "read-only",
    writeMode: "agent", env: {"FIXTURE_LOG": result / "fixture.log"}.toTable())
  cfg.agents.architect.acpAgent = "fixture"
  cfg.agents.architect.model = ""
  writeFile(result / "scriptorium.json", cfg.toJson())

proc connectServer(repo: string, url = true): AcpClient =
  ## Attach a client to a fresh `scriptorium architect-acp` process.
  discard drainUpdates()
  var handlers = ClientHandlers(onUpdate: collectUpdate, onPermission: answerPermission,
    onElicitationForm: answerQuestion)
  if url:
    handlers.onElicitationUrl = answerConsent
    handlers.onElicitationComplete = collectCompletion
  result = newAcpClient("architect-acp-test", "1", handlers)
  result.connect(binary, @["architect-acp"], workingDir = repo)
  discard result.initialize(TimeoutMs)

proc newArchitectSession(client: AcpClient, repo: string): AcpSession =
  ## Open an outer session with the protected tools and instructions Guildhall supplies.
  client.newSession(repo, @[%*{"type": "http", "name": "campfire", "url": SecretUrl,
    "headers": [{"name": "Authorization", "value": SecretHeader}]}], TimeoutMs,
    systemPrompt = some(SystemPrompt(mode: "append", content: @[textBlock(SecretInstructions)])))

proc ask(session: AcpSession, text: string): tuple[stop: StopReason, items: seq[JsonNode]] =
  ## Run one text prompt and return its stop reason and streamed updates.
  let response = session.prompt(@[textBlock(text)], TimeoutMs)
  result = (response.stopReason, drainUpdates())

proc processAlive(pid: int): bool =
  ## Check whether a process still exists.
  posix.kill(Pid(pid), 0) == 0

proc childrenExited(repo: string) =
  ## Require every scripted agent process the server launched to be gone.
  var waited = 0
  for entry in fixtureLog(repo):
    while processAlive(entry["pid"].getInt()) and waited < CleanupWaitMs:
      sleep(PollMs)
      waited += PollMs
    check not processAlive(entry["pid"].getInt())

proc adminLockHeld(repo: string): bool =
  ## Report whether an Architect turn currently holds the admin lock.
  dirExists(managedAdminLockPath(repo))

suite "architect ACP bridge":
  test "stdio framing, structured streaming, forwarded setup and owned cleanup":
    let repo = makeRepo()
    defer: removeDir(repo)
    let client = connectServer(repo)
    var closed = false
    defer:
      if not closed: client.close()
    let session = client.newArchitectSession(repo)
    check session.state.configOptions[0]["currentValue"].getStr() == "plan"
    let (stop, items) = session.ask("fixture:stream")
    check stop == endTurn
    var kinds: seq[string]
    for item in items:
      check item["sessionId"].getStr() == session.id
      kinds.add(item["update"]["sessionUpdate"].getStr())
    check "agent_thought_chunk" in kinds
    check "tool_call" in kinds
    check "tool_call_update" in kinds
    check "plan" in kinds
    check "user_message_chunk" notin kinds
    check "available_commands_update" notin kinds
    check messageText(items) == "stream-tail"
    check not adminLockHeld(repo)
    var created = false
    for entry in fixtureLog(repo):
      if entry["method"].getStr() == "session/new":
        created = true
        check entry["mcpServers"] == %*["campfire"]
        check entry["systemPrompt"].getStr() == SecretInstructions
    check created
    for path in walkDirRec(repo / ".scriptorium" / "architect-acp"):
      let content = readFile(path)
      check "secret-scope" notin content
      check "secret-token" notin content
      check SecretInstructions notin content
    client.close()
    closed = true
    childrenExited(repo)

  test "content blocks reach the Architect and capabilities follow the native agent":
    let repo = makeRepo()
    defer: removeDir(repo)
    let client = connectServer(repo)
    defer: client.close()
    let session = client.newArchitectSession(repo)
    let response = session.prompt(@[textBlock("fixture:image"),
      ContentBlock(kind: imageContent, data: PngPixel, mimeType: "image/png"),
      resourceLink("file:///workspace/notes.txt", "notes.txt")], TimeoutMs)
    check response.stopReason == endTurn
    check messageText(drainUpdates()) == "text,image,resource_link-tail"
    expect AcpRpcError:
      discard session.prompt(@[textBlock("fixture:image"),
        ContentBlock(kind: audioContent, data: "AAAA", mimeType: "audio/wav")], TimeoutMs)
    check promptCount(repo) == 1

  test "questions and permissions are forwarded without widening mode policy":
    let repo = makeRepo()
    defer: removeDir(repo)
    let client = connectServer(repo)
    defer: client.close()
    let session = client.newArchitectSession(repo)
    let (_, answered) = session.ask("fixture:elicit")
    check messageText(answered) == "accept:{\"color\":\"blue\"}-tail"
    let question = parseJson(questions.recv())
    check question["sessionId"].getStr() == session.id
    check question["message"].getStr() == "Pick a color"
    atomicStoreN(addr permissionsAsked, 0, ATOMIC_RELEASE)
    atomicStoreN(addr allowPermissions, true, ATOMIC_RELEASE)
    check messageText(session.ask("fixture:permission-spec").items) == "yes-tail"
    atomicStoreN(addr allowPermissions, false, ATOMIC_RELEASE)
    check messageText(session.ask("fixture:permission-spec").items) == "no-tail"
    atomicStoreN(addr allowPermissions, true, ATOMIC_RELEASE)
    check messageText(session.ask("fixture:permission").items) == "no-tail"
    check atomicLoadN(addr permissionsAsked, ATOMIC_ACQUIRE) == 2
    check messageText(session.ask("fixture:settings").items) == "fixture-model:high:agent-tail"
    check messageText(session.ask("fixture:ticket").items) == "ticket-tail"
    check gitCheck(repo, "cat-file", "-e", PlanBranch & ":tickets/open/0099-fixture.md") == 0
    check not adminLockHeld(repo)
    check ContextMarker notin lastPromptText(repo)
    let options = session.setConfigOption("mode", "ask", TimeoutMs)
    check options[0].currentValue.stringValue == "ask"
    discard drainUpdates()
    check messageText(session.ask("fixture:settings").items) == "fixture-model:high:read-only-tail"
    check ContextMarker in lastPromptText(repo)
    check "Engineer (plan mode): fixture:ticket" in lastPromptText(repo)
    check "do not authorize any action" in lastPromptText(repo)
    check messageText(session.ask("fixture:permission-spec").items) == "no-tail"
    check ContextMarker notin lastPromptText(repo)
    check atomicLoadN(addr permissionsAsked, ATOMIC_ACQUIRE) == 2

  test "URL consent and completion are forwarded only when the client advertises them":
    let repo = makeRepo()
    defer: removeDir(repo)
    block:
      let client = connectServer(repo)
      defer: client.close()
      let session = client.newArchitectSession(repo)
      check messageText(session.ask("fixture:elicit-url").items) == "accept-tail"
      let consent = parseJson(consents.recv())
      check consent["mode"].getStr() == "url"
      check consent["sessionId"].getStr() == session.id
      check consent["url"].getStr() == "https://example.invalid/consent"
      check consent["elicitationId"].getStr() == "flow-1"
      var completed = ""
      waitFor(proc(): bool =
        let (received, id) = completions.tryRecv()
        if received: completed = id
        received)
      check completed == "flow-1"
      check messageText(session.ask("fixture:elicit-file-url").items) == "decline-tail"
      check not consents.tryRecv().dataAvailable
    let client = connectServer(repo, url = false)
    defer: client.close()
    let session = client.newArchitectSession(repo)
    check messageText(session.ask("fixture:elicit-url").items) == "no-url-tail"
    check not consents.tryRecv().dataAvailable
    check not completions.tryRecv().dataAvailable

  test "images persist privately and replay with identical bytes after server recreation":
    let repo = makeRepo()
    defer: removeDir(repo)
    let
      pixel = decode(PngPixel)
      digest = digestHex(pixel)
      state = repo / ".scriptorium" / "architect-acp"
    var sessionId = ""
    block:
      let client = connectServer(repo)
      defer: client.close()
      let session = client.newArchitectSession(repo)
      sessionId = session.id
      let response = session.prompt(@[textBlock("fixture:image"),
        ContentBlock(kind: imageContent, data: PngPixel, mimeType: "image/png"),
        resourceLink("file:///workspace/notes.txt", "notes.txt")], TimeoutMs)
      check response.stopReason == endTurn
      discard drainUpdates()
      for invalid in [ContentBlock(kind: imageContent, data: PngPixel, mimeType: "image/jpeg"),
          ContentBlock(kind: imageContent, data: encode(pngHeader(9000, 1)), mimeType: "image/png"),
          ContentBlock(kind: imageContent, data: "not base64!", mimeType: "image/png")]:
        expect AcpRpcError:
          discard session.prompt(@[textBlock("fixture:image"), invalid], TimeoutMs)
      check promptCount(repo) == 1
    let media = state / (sessionId & "-media")
    var stored: seq[string]
    for path in walkDir(media): stored.add(path.path.extractFilename)
    check stored == @[digest]
    check getFilePermissions(media) == {fpUserRead, fpUserWrite, fpUserExec}
    check getFilePermissions(media / digest) == {fpUserRead, fpUserWrite}
    check readFile(media / digest) == pixel
    let transcript = readFile(state / (sessionId & ".jsonl"))
    check PngPixel notin transcript
    check digest in transcript
    check gitCheck(repo, "check-ignore", "-q", media / digest) == 0
    check "architect-acp" notin execCmdEx("git -C " & quoteShell(repo) &
      " status --porcelain --untracked-files=all").output

    proc replayImages(): seq[JsonNode] =
      ## Load the session in a fresh server and return the replayed image blocks.
      let client = connectServer(repo)
      defer: client.close()
      discard client.loadSession(sessionId, repo, timeoutMs = TimeoutMs)
      let replayed = drainUpdates()
      check messageText(replayed, "user_message_chunk").startsWith("fixture:image")
      result = imageChunks(replayed)

    let restored = replayImages()
    check restored.len == 1
    check restored[0]["mimeType"].getStr() == "image/png"
    check decode(restored[0]["data"].getStr()) == pixel
    check promptCount(repo) == 1

    let outside = repo / "outside.png"
    writeFile(outside, pixel)
    writeFile(state / (sessionId & ".jsonl"), transcript.replace(digest, "../../../outside.png"))
    check replayImages().len == 0
    writeFile(state / (sessionId & ".jsonl"), transcript)
    writeFile(media / digest, pixel & "tampered")
    check replayImages().len == 0
    writeFile(media / digest, pixel)
    check replayImages().len == 1

  test "restart restores the native identity and replays the durable conversation":
    let repo = makeRepo()
    defer: removeDir(repo)
    var sessionId = ""
    block:
      let client = connectServer(repo)
      defer: client.close()
      let session = client.newArchitectSession(repo)
      sessionId = session.id
      check messageText(session.ask("fixture:hello").items) == "hello-tail"
    let client = connectServer(repo)
    defer: client.close()
    let listed = client.listSessions(some(repo), timeoutMs = TimeoutMs)
    check listed.sessions.len == 1
    check listed.sessions[0].sessionId == sessionId
    let session = client.loadSession(sessionId, repo, timeoutMs = TimeoutMs)
    let replayed = drainUpdates()
    for item in replayed: check item["sessionId"].getStr() == sessionId
    check messageText(replayed, "user_message_chunk") == "fixture:hello"
    check messageText(replayed) == "hello-tail"
    check messageText(session.ask("fixture:hello").items) == "hello-tail"
    var loads = 0
    for entry in fixtureLog(repo):
      if entry["method"].getStr() == "session/load": inc loads
    check loads == 1

  test "an interrupted prompt is not executed again automatically":
    let repo = makeRepo()
    defer: removeDir(repo)
    var sessionId = ""
    block:
      let client = connectServer(repo)
      defer: client.close()
      let session = client.newArchitectSession(repo)
      sessionId = session.id
      var handle = session.startPrompt(@[textBlock("fixture:ticket-hang")])
      waitFor(proc(): bool = promptCount(repo) == 1)
      let server = fixtureLog(repo)[^1]["ppid"].getInt()
      check posix.kill(Pid(server), SIGKILL) == 0
      expect AcpError:
        discard handle.waitForPrompt(TimeoutMs)
    let client = connectServer(repo)
    defer: client.close()
    let session = client.loadSession(sessionId, repo, timeoutMs = TimeoutMs)
    check "interrupted before its outcome was recorded" in messageText(drainUpdates())
    check promptCount(repo) == 1
    let (stop, declined) = session.ask("fixture:ticket-hang")
    check stop == endTurn
    check "did not run this request" in messageText(declined)
    check promptCount(repo) == 1
    check gitCheck(repo, "cat-file", "-e", PlanBranch & ":tickets/open/0099-fixture.md") != 0
    check messageText(session.ask("fixture:hello").items) == "hello-tail"
    check promptCount(repo) == 2

  test "commands pause and report status without the model":
    let repo = makeRepo()
    defer: removeDir(repo)
    let client = connectServer(repo)
    defer: client.close()
    let session = client.newArchitectSession(repo)
    check "paused" in messageText(session.ask("/pause").items)
    check isPaused(repo)
    check "Orchestrator: not running, paused" in messageText(session.ask("/status").items)
    check "No orchestrator is running" in messageText(session.ask("/start").items)
    check isPaused(repo)
    check promptCount(repo) == 0
    let (output, code) = execCmdEx(quoteShell(binary) & " guildhall-control status",
      options = {poUsePath}, workingDir = repo)
    check code == 0
    let status = parseJson(output)
    check status["orchestrator"]["paused"].getBool()
    check not status["orchestrator"]["running"].getBool()
    check status["tickets"]["open"].getInt() == 0
    check status["agents"]["agents"].len == 0
    check status["mergeQueue"]["pending"].len == 0
    check execCmdEx(quoteShell(binary) & " guildhall-control start", workingDir = repo).exitCode != 0

  test "cancellation ends the turn, releases the lock, and the session continues":
    let repo = makeRepo()
    defer: removeDir(repo)
    let client = connectServer(repo)
    var closed = false
    defer:
      if not closed: client.close()
    let session = client.newArchitectSession(repo)
    var handle = session.startPrompt(@[textBlock("fixture:silent")])
    waitFor(proc(): bool = promptCount(repo) == 1)
    check adminLockHeld(repo)
    session.cancel()
    check handle.waitForPrompt(TimeoutMs).stopReason == cancelled
    check not adminLockHeld(repo)
    check messageText(session.ask("fixture:hello").items) == "hello-tail"
    check not adminLockHeld(repo)
    client.close()
    closed = true
    childrenExited(repo)
