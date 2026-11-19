import
  std/[json, os, posix, strutils]

const
  CommandMarker = "fixture:"
  FixtureTicket = "tickets/open/0099-fixture.md"

proc send(node: JsonNode) =
  ## Write exactly one independent raw-wire protocol message.
  stdout.writeLine($node)
  stdout.flushFile()

proc respond(id, value: JsonNode) =
  ## Reply to a client request using its exact identifier.
  send(%*{"jsonrpc": "2.0", "id": id, "result": value})

proc update(payload: JsonNode) =
  ## Send an update associated with the fixture's session.
  send(%*{"jsonrpc": "2.0", "method": "session/update",
    "params": {"sessionId": "fixture-session", "update": payload}})

proc record(entry: JsonNode) =
  ## Append one observation to the log a test selected through the profile environment.
  let path = getEnv("FIXTURE_LOG")
  if path.len > 0:
    entry["pid"] = %getCurrentProcessId()
    entry["ppid"] = %getppid().int
    let output = open(path, fmAppend)
    output.writeLine($entry)
    output.close()

proc catalog(model, effort, mode: string): JsonNode =
  ## Advertise configuration with dependent choices and a legacy mode catalog.
  %*[
    {"id": "model", "name": "Model", "category": "model", "type": "select",
      "currentValue": model, "options": [{"value": "fixture-model", "name": "Fixture"}]},
    {"id": "effort", "name": "Effort", "category": "thought_level", "type": "select",
      "currentValue": effort, "options": [{"value": "high", "name": "High"}]},
    {"id": "mode", "name": "Mode", "category": "mode", "type": "select",
      "currentValue": mode, "options": [{"value": "read-only", "name": "Read only"},
        {"value": "agent", "name": "Agent"}]}
  ]

proc commandOf(text: string): string =
  ## Select the last embedded fixture command, or the whole text for direct runner tests.
  let index = text.rfind(CommandMarker)
  if index < 0: text
  else: text[index + CommandMarker.len .. ^1].splitWhitespace()[0]

proc writeTicket(cwd: string) =
  ## Create an uncommitted ticket the way a planning agent would.
  createDir(cwd / FixtureTicket.parentDir)
  writeFile(cwd / FixtureTicket, "# Fixture ticket\n\n**Area:** fixture\n")

proc main() =
  ## Exercise application lifecycle behavior without using a real AI provider.
  var
    cwd = ""
    model = "fixture-model"
    effort = "high"
    mode = "agent"
    urlElicitation = false
    pending: JsonNode
  while not stdin.endOfFile():
    let node = parseJson(stdin.readLine())
    let
      methodName = node.getOrDefault("method").getStr()
      params = node.getOrDefault("params")
      id = node.getOrDefault("id")
    case methodName
    of "initialize":
      urlElicitation = params{"clientCapabilities", "elicitation", "url"} != nil
      respond(id, %*{"protocolVersion": 1, "agentInfo": {"name": "fixture", "version": "1"},
        "agentCapabilities": {"loadSession": true, "promptCapabilities": {"image": true},
          "mcpCapabilities": {"http": true}, "sessionCapabilities": {"systemPrompt": {}}},
        "authMethods": []})
    of "session/new", "session/load":
      cwd = params["cwd"].getStr()
      var servers = newJArray()
      for server in params["mcpServers"]: servers.add(server{"name"})
      var instructions = ""
      let system = params{"systemPrompt"}{"content"}
      if system != nil and system.kind == JArray:
        for content in system: instructions.add(content{"text"}.getStr())
      record(%*{"method": methodName, "cwd": cwd, "mcpServers": servers,
        "systemPrompt": instructions})
      if methodName == "session/load":
        update(%*{"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "REPLAY"}})
      respond(id, %*{"sessionId": "fixture-session", "configOptions": catalog(model, effort, mode)})
    of "session/set_config_option":
      case params["configId"].getStr()
      of "model": model = params["value"].getStr()
      of "effort": effort = params["value"].getStr()
      of "mode": mode = params["value"].getStr()
      else: raise newException(ValueError, "Unexpected option")
      respond(id, %*{"configOptions": catalog(model, effort, mode)})
    of "session/prompt":
      let
        text = params["prompt"][0]["text"].getStr()
        command = commandOf(text)
      var types: seq[string]
      for content in params["prompt"]: types.add(content["type"].getStr())
      record(%*{"method": methodName, "command": command, "types": types, "text": text})
      if command == "disconnect": quit(0)
      if command == "error":
        send(%*{"jsonrpc": "2.0", "id": id,
          "error": {"code": -32010, "message": "fixture error", "data": {"detail": "retained"}}})
      elif command == "silent":
        pending = id
      elif command == "ticket-hang":
        writeTicket(cwd)
        pending = id
      else:
        var reply = command
        if command in ["permission", "permission-spec"]:
          let target = if command == "permission": cwd / "allowed.txt" else: cwd / "spec.md"
          send(%*{"jsonrpc": "2.0", "id": "permission", "method": "session/request_permission",
            "params": {"sessionId": "fixture-session", "toolCall": {"toolCallId": "edit-1",
              "title": "Write", "kind": "edit", "locations": [{"path": target}]},
              "options": [{"optionId": "yes", "name": "Allow", "kind": "allow_once"},
                {"optionId": "always", "name": "Always", "kind": "allow_always"},
                {"optionId": "no", "name": "Reject", "kind": "reject_once"}]}})
          let decision = parseJson(stdin.readLine())
          reply = decision["result"]["outcome"].getOrDefault("optionId").getStr("cancelled")
        elif command == "elicit":
          send(%*{"jsonrpc": "2.0", "id": "question", "method": "elicitation/create",
            "params": {"sessionId": "fixture-session", "mode": "form", "message": "Pick a color",
              "requestedSchema": {"type": "object", "properties": {"color": {"type": "string"}}}}})
          let answer = parseJson(stdin.readLine())["result"]
          reply = answer["action"].getStr() & ":" & $answer{"content"}
        elif command in ["elicit-url", "elicit-file-url"]:
          if urlElicitation:
            let url = if command == "elicit-url": "https://example.invalid/consent" else: "file:///etc/passwd"
            send(%*{"jsonrpc": "2.0", "id": "consent", "method": "elicitation/create",
              "params": {"sessionId": "fixture-session", "mode": "url", "message": "Approve access",
                "elicitationId": "flow-1", "url": url}})
            reply = parseJson(stdin.readLine())["result"]["action"].getStr()
            if reply == "accept":
              send(%*{"jsonrpc": "2.0", "method": "elicitation/complete",
                "params": {"elicitationId": "flow-1"}})
          else:
            reply = "no-url"
        elif command == "image":
          reply = types.join(",")
        elif command == "stream":
          update(%*{"sessionUpdate": "user_message_chunk", "content": {"type": "text", "text": "echo"}})
          update(%*{"sessionUpdate": "available_commands_update", "availableCommands": []})
          update(%*{"sessionUpdate": "agent_thought_chunk", "content": {"type": "text", "text": "thinking"}})
          update(%*{"sessionUpdate": "tool_call", "toolCallId": "read-1", "title": "Read spec",
            "kind": "read", "status": "pending"})
          update(%*{"sessionUpdate": "tool_call_update", "toolCallId": "read-1", "status": "completed"})
          update(%*{"sessionUpdate": "plan", "entries": [{"content": "Revise spec",
            "priority": "high", "status": "in_progress"}]})
        elif command == "ticket":
          writeTicket(cwd)
        elif command == "noise":
          stderr.writeLine("diagnostic noise")
          stderr.flushFile()
          sleep(200)
        elif command == "unknown":
          update(%*{"sessionUpdate": "future_update", "future": true, "_meta": {"retained": true}})
        elif command == "settings":
          reply = model & ":" & effort & ":" & mode
        for chunk in [reply, "-tail"]:
          update(%*{"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": chunk}})
        respond(id, %*{"stopReason": "end_turn"})
    of "session/cancel":
      if pending != nil:
        respond(pending, %*{"stopReason": "cancelled"})
        pending = nil
    of "$/cancel_request": discard
    else: raise newException(ValueError, "Unexpected method: " & methodName)

main()
