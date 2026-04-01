import
  std/[strutils],
  ./[agent_runner, logging]

proc extractFileActivity*(toolText: string): string =
  ## Parse tool event text to detect file activity (read/write) and return
  ## a summary string like "read path/to/file", or empty string if none found.
  var
    toolName = ""
    rest = ""
    splitIdx = -1

  # Find the first space to split tool name from arguments.
  splitIdx = toolText.find(' ')
  if splitIdx < 0:
    return ""

  toolName = toolText[0 ..< splitIdx].strip()
  rest = toolText[splitIdx + 1 .. ^1].strip()

  if rest.len == 0:
    return ""

  # Determine the activity type based on tool name.
  var activity = ""
  case toolName
  of "Read", "read_file":
    activity = "read"
  of "Edit", "Write", "edit_file", "write_file", "create_file":
    activity = "write"
  of "Bash":
    # Best-effort: check if the bash command references file operations.
    let lower = rest.toLowerAscii()
    if lower.startsWith("cat ") or lower.startsWith("head ") or
       lower.startsWith("tail ") or lower.startsWith("less "):
      activity = "read"
    elif lower.startsWith("cp ") or lower.startsWith("mv ") or
         lower.startsWith("mkdir ") or lower.startsWith("touch ") or
         lower.startsWith("tee "):
      activity = "write"
    else:
      return ""
  else:
    return ""

  # Extract a file path from the rest of the text.
  # Take the first token that looks like a path (contains / or .)
  # and does not start with a dash (flag).
  let tokens = rest.split(' ')
  for t in tokens:
    let stripped = t.strip()
    if stripped.len > 0 and stripped[0] != '-' and
       (stripped.contains('/') or stripped.contains('.')):
      return activity & " " & stripped

  return ""

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
    let fileActivity = extractFileActivity(event.text)
    if fileActivity.len > 0:
      let fileLine = prefix & ": file " & fileActivity
      logInfo(fileLine)
  of agentEventStatus:
    let prefix = role & "[" & identifier & "]"
    let statusLine = prefix & ": status " & event.text
    logInfo(statusLine)
  of agentEventHeartbeat:
    discard
  of agentEventReasoning:
    discard
  of agentEventMessage:
    discard
