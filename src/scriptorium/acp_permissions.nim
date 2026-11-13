import
  std/[json, options, os, strutils],
  acport,
  ./[agent_runner_types]

proc physicalPath(path: string): string =
  ## Resolve existing ancestors so new files cannot escape through a symlink.
  if fileExists(path) or dirExists(path) or symlinkExists(path):
    return expandFilename(path)
  let parent = path.parentDir
  if parent == path: return path
  physicalPath(parent) / path.extractFilename()

proc pathAllowed*(path, cwd: string, allowed: seq[string]): bool =
  ## Check physical reported paths against explicit operation write roots.
  if path.len == 0: return false
  let absolute = physicalPath(normalizedPath(absolutePath(path, cwd)))
  for entry in allowed:
    let root = physicalPath(normalizedPath(absolutePath(entry, cwd)))
    if absolute == root or absolute.startsWith(root & DirSep):
      return true

proc permissionOutcome*(request: PermissionRequest, policy: AgentAccessPolicy,
    cwd: string, writePaths: seq[string]): PermissionOutcome =
  ## Select a per-action decision without granting broader durable access.
  let tool = request.toolCall
  var permit = policy == accessFull
  if policy != accessFull:
    permit = tool.kind in ["read", "search", "fetch", "think"]
    if policy == accessRestricted and tool.kind == "edit" and
        tool.locations.isSome() and tool.locations.get().len > 0:
      permit = true
      for location in tool.locations.get():
        if not pathAllowed(location.path, cwd, writePaths): permit = false
  let kind = if permit: "allow_once" else: "reject_once"
  for option in request.options:
    if option.kind == kind:
      return PermissionOutcome(outcome: "selected", optionId: option.optionId)
  PermissionOutcome(outcome: "cancelled")
