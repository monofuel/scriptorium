import
  std/[options, strutils],
  ./[agent_runner, logging]

proc forwardAgentEvent*(role: string, identifier: string,
                        event: AgentStreamEvent) =
  ## Forward meaningful agent stream events to orchestrator logs.
  ## Tool and status events are logged at INFO level; heartbeat, reasoning,
  ## and message events are silently skipped.
  case event.kind
  of agentEventTool:
    let prefix = role & "[" & identifier & "]"
    let toolLine = prefix & ": tool " & event.text
    logInfo(toolLine)
    let tool = event.update.tool
    if tool.locations.isSome() and tool.kind in ["read", "edit", "delete", "move"]:
      let action = if tool.kind == "read": "read" else: "write"
      for location in tool.locations.get():
        logInfo(prefix & ": file " & action & " " & location.path)
  of agentEventStatus, agentEventPlan:
    let prefix = role & "[" & identifier & "]"
    let statusLine = prefix & ": status " & event.text
    logInfo(statusLine)
  of agentEventHeartbeat:
    discard
  of agentEventReasoning:
    discard
  of agentEventMessage, agentEventUnknown:
    discard
