import
  std/[json, os, strutils]

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

proc main() =
  ## Exercise application lifecycle behavior without using a real AI provider.
  var
    cwd = ""
    model = "fixture-model"
    effort = "high"
    mode = "agent"
    pending: JsonNode
  while not stdin.endOfFile():
    let node = parseJson(stdin.readLine())
    let
      methodName = node.getOrDefault("method").getStr()
      params = node.getOrDefault("params")
      id = node.getOrDefault("id")
    case methodName
    of "initialize":
      respond(id, %*{"protocolVersion": 1, "agentInfo": {"name": "fixture", "version": "1"},
        "agentCapabilities": {"loadSession": true}, "authMethods": []})
    of "session/new", "session/load":
      cwd = params["cwd"].getStr()
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
      let text = params["prompt"][0]["text"].getStr()
      if text == "disconnect": quit(0)
      if text == "error":
        send(%*{"jsonrpc": "2.0", "id": id,
          "error": {"code": -32010, "message": "fixture error", "data": {"detail": "retained"}}})
      elif text == "silent":
        pending = id
      else:
        var reply = text
        if text == "permission":
          send(%*{"jsonrpc": "2.0", "id": "permission", "method": "session/request_permission",
            "params": {"sessionId": "fixture-session", "toolCall": {"toolCallId": "edit-1",
              "title": "Write", "kind": "edit", "locations": [{"path": cwd / "allowed.txt"}]},
              "options": [{"optionId": "yes", "name": "Allow", "kind": "allow_once"},
                {"optionId": "no", "name": "Reject", "kind": "reject_once"}]}})
          let decision = parseJson(stdin.readLine())
          reply = decision["result"]["outcome"].getOrDefault("optionId").getStr("cancelled")
        elif text == "noise":
          stderr.writeLine("diagnostic noise")
          stderr.flushFile()
          sleep(200)
        elif text == "unknown":
          update(%*{"sessionUpdate": "future_update", "future": true, "_meta": {"retained": true}})
        elif text == "settings":
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
