import
  std/[json, options, os, posix, strutils, unicode],
  mcport,
  ./git_ops

const
  ProjectReadServerName* = "scriptorium-project"
  MaxProjectTextBytes* = 1_048_576
  DefaultReadLines = 200
  MaxReadLines = 500

var
  NoFollow {.importc: "O_NOFOLLOW", header: "<fcntl.h>".}: cint
  DirectoryOnly {.importc: "O_DIRECTORY", header: "<fcntl.h>".}: cint
  CloseOnExec {.importc: "O_CLOEXEC", header: "<fcntl.h>".}: cint

proc openAt(directory: cint, path: cstring, flags: cint): cint {.importc: "openat", header: "<fcntl.h>".}
  ## Open a child relative to an already validated directory descriptor.

proc readScopedText(root, relative: string): string =
  ## Read a bounded regular text file without following any path-component symlinks.
  if relative.len == 0 or relative.isAbsolute() or '\\' in relative:
    raise newException(ValueError, "Expected a project-relative file path")
  let parts = relative.split('/')
  for part in parts:
    if part.len == 0 or part in [".", "..", ".git", ".scriptorium", ".guildhall", ".ssh",
        ".aws", ".codex", ".claude", ".hermes", ".env"]:
      raise newException(ValueError, "Private or traversing project paths are not readable")
  var directory = posix.open(root.cstring, O_RDONLY or DirectoryOnly or NoFollow or CloseOnExec)
  if directory < 0: raiseOSError(osLastError())
  defer: discard posix.close(directory)
  for part in parts[0 ..< parts.high]:
    let child = openAt(directory, part.cstring, O_RDONLY or DirectoryOnly or NoFollow or CloseOnExec)
    if child < 0: raiseOSError(osLastError())
    discard posix.close(directory)
    directory = child
  let file = openAt(directory, parts[^1].cstring, O_RDONLY or NoFollow or O_NONBLOCK or CloseOnExec)
  if file < 0: raiseOSError(osLastError())
  defer: discard posix.close(file)
  var info: Stat
  if fstat(file, info) != 0: raiseOSError(osLastError())
  if not S_ISREG(info.st_mode) or info.st_size > MaxProjectTextBytes:
    raise newException(ValueError, "Project reads require a regular text file of at most 1 MiB")
  var buffer: array[8192, char]
  while true:
    let count = posix.read(file, addr buffer[0], buffer.len)
    if count < 0: raiseOSError(osLastError())
    if count == 0: break
    if result.len + count > MaxProjectTextBytes:
      raise newException(ValueError, "Project text exceeds the 1 MiB read bound")
    let previous = result.len
    result.setLen(previous + count)
    copyMem(addr result[previous], addr buffer[0], count)
  if '\0' in result or validateUtf8(result) != -1:
    raise newException(ValueError, "Project reads require UTF-8 text, not binary data")

proc requireArguments(arguments: JsonNode, allowed: openArray[string]) =
  ## Reject missing objects or unknown fields before accessing file parameters.
  if arguments.isNil or arguments.kind != JObject:
    raise newException(ValueError, "Tool arguments must be an object")
  for key in arguments.keys:
    if key notin allowed: raise newException(ValueError, "Unknown project-read argument: " & key)

proc newProjectReadServer*(repoPath, planPath: string): McpServer =
  ## Expose only the current spec and tracked project text through explicit read-only MCP tools.
  let
    project = expandFilename(repoPath)
    plan = expandFilename(planPath)
    annotations = some(%*{"readOnlyHint": true, "destructiveHint": false,
      "idempotentHint": true, "openWorldHint": false})
  result = newMcpServer(ProjectReadServerName, "1")
  result.toolsOnly = true
  let getSpec: RichToolHandler = proc(arguments: JsonNode): ToolResult {.gcsafe.} =
    requireArguments(arguments, [])
    let payload = %*{"path": "spec.md", "text": readScopedText(plan, "spec.md")}
    ToolResult(content: @[mcport.textContent($payload)], structuredContent: some(payload))
  result.registerRichTool(McpTool(name: "get_spec", description: "Read the actual current Scriptorium plan specification.",
    inputSchema: %*{"type": "object", "properties": {}, "additionalProperties": false},
    annotations: annotations), getSpec)
  let readProject: RichToolHandler = proc(arguments: JsonNode): ToolResult {.gcsafe.} =
    requireArguments(arguments, ["path", "line", "limit"])
    if not arguments.hasKey("path") or arguments["path"].kind != JString:
      raise newException(ValueError, "A project-relative path string is required")
    let path = arguments["path"].getStr()
    var
      first = 1
      limit = DefaultReadLines
    for key in ["line", "limit"]:
      if arguments.hasKey(key):
        if arguments[key].kind != JInt: raise newException(ValueError, key & " must be an integer")
        if key == "line": first = arguments[key].getInt()
        else: limit = arguments[key].getInt()
    if first < 1 or limit < 1 or limit > MaxReadLines:
      raise newException(ValueError, "Expected line >= 1 and limit between 1 and 500")
    let tracked = gitRunCapture(project, @["--literal-pathspecs", "ls-files", "--error-unmatch", "--", path])
    if tracked.exitCode != 0:
      raise newException(ValueError, "Only tracked project files are readable")
    let
      text = readScopedText(project, path)
      lines = text.splitLines()
      start = min(first - 1, lines.len)
      stop = start + min(limit, lines.len - start)
    let payload = %*{"path": path, "line": first, "text": lines[start ..< stop].join("\n"),
      "nextLine": (if stop < lines.len: %(stop + 1) else: newJNull())}
    ToolResult(content: @[mcport.textContent($payload)], structuredContent: some(payload))
  result.registerRichTool(McpTool(name: "read_project_file",
    description: "Read tracked UTF-8 project files such as AGENTS.md or source; no shell, writes, private state, or symlinks.",
    inputSchema: %*{"type": "object", "properties": {"path": {"type": "string"},
      "line": {"type": "integer", "minimum": 1},
      "limit": {"type": "integer", "minimum": 1, "maximum": MaxReadLines}},
      "required": ["path"], "additionalProperties": false}, annotations: annotations), readProject)
