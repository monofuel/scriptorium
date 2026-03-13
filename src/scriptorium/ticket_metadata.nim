import
  std/[algorithm, os, strformat, strutils],
  ./shared_state

const
  AreaFieldPrefix* = "**Area:**"
  DependsFieldPrefix* = "**Depends:**"
  WorktreeFieldPrefix* = "**Worktree:**"

proc normalizeAreaPath*(rawPath: string): string =
  ## Validate and normalize a relative area path.
  let clean = rawPath.strip()
  if clean.len == 0:
    raise newException(ValueError, "area path cannot be empty")
  if clean.startsWith("/") or clean.startsWith("\\"):
    raise newException(ValueError, fmt"area path must be relative: {clean}")
  if clean.startsWith("..") or clean.contains("/../") or clean.contains("\\..\\"):
    raise newException(ValueError, fmt"area path cannot escape areas directory: {clean}")
  if not clean.toLowerAscii().endsWith(".md"):
    raise newException(ValueError, fmt"area path must be a markdown file: {clean}")
  result = clean

proc normalizeTicketSlug*(rawSlug: string): string =
  ## Validate and normalize a ticket slug for filename usage.
  let clean = rawSlug.strip().toLowerAscii()
  if clean.len == 0:
    raise newException(ValueError, "ticket slug cannot be empty")

  var slug = ""
  for ch in clean:
    if ch in {'a'..'z', '0'..'9'}:
      slug.add(ch)
    elif ch in {' ', '-', '_'}:
      if slug.len > 0 and slug[^1] != '-':
        slug.add('-')

  if slug.endsWith("-"):
    slug.setLen(slug.len - 1)
  if slug.len == 0:
    raise newException(ValueError, "ticket slug must contain alphanumeric characters")
  result = slug

proc areaIdFromAreaPath*(areaRelPath: string): string =
  ## Derive the area identifier from an area file path.
  result = splitFile(areaRelPath).name

proc ticketIdFromTicketPath*(ticketRelPath: string): string =
  ## Extract the numeric ticket identifier prefix from a ticket path.
  let fileName = splitFile(ticketRelPath).name
  let dashPos = fileName.find('-')
  if dashPos < 1:
    raise newException(ValueError, fmt"ticket filename has no numeric prefix: {fileName}")
  let id = fileName[0..<dashPos]
  if not id.allCharsInSet(Digits):
    raise newException(ValueError, fmt"ticket filename has non-numeric prefix: {fileName}")
  result = id

proc parseAreaFromTicketContent*(ticketContent: string): string =
  ## Extract the area identifier from a ticket markdown body.
  for line in ticketContent.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith(AreaFieldPrefix):
      result = trimmed[AreaFieldPrefix.len..^1].strip()
      break

proc parseDependsFromTicketContent*(ticketContent: string): seq[string] =
  ## Extract dependency ticket IDs from a ticket markdown body.
  for line in ticketContent.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith(DependsFieldPrefix):
      let raw = trimmed[DependsFieldPrefix.len..^1].strip()
      if raw.len > 0:
        for part in raw.split(","):
          let id = part.strip()
          if id.len > 0:
            result.add(id)
      break

proc parseWorktreeFromTicketContent*(ticketContent: string): string =
  ## Extract the worktree path from a ticket markdown body.
  for line in ticketContent.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith(WorktreeFieldPrefix):
      let value = trimmed[WorktreeFieldPrefix.len..^1].strip()
      if value.len > 0 and value != "—" and value != "-":
        result = value
      break

proc setTicketWorktree*(ticketContent: string, worktreePath: string): string =
  ## Set or append the ticket worktree metadata field.
  var lines = ticketContent.strip().splitLines()
  var updated = false
  for i in 0..<lines.len:
    if lines[i].strip().startsWith(WorktreeFieldPrefix):
      lines[i] = WorktreeFieldPrefix & " " & worktreePath
      updated = true
      break
  if not updated:
    lines.add("")
    lines.add(WorktreeFieldPrefix & " " & worktreePath)
  result = lines.join("\n") & "\n"

proc listMarkdownFiles*(basePath: string): seq[string] =
  ## Collect markdown files recursively and return sorted absolute paths.
  if not dirExists(basePath):
    result = @[]
  else:
    for filePath in walkDirRec(basePath):
      if filePath.toLowerAscii().endsWith(".md"):
        result.add(filePath)
    result.sort()

proc parseQueueField*(content: string, prefix: string): string =
  ## Parse one single-line markdown field from queue item content.
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith(prefix):
      result = trimmed[prefix.len..^1].strip()
      break

proc queueItemToMarkdown*(item: MergeQueueItem): string =
  ## Convert one merge queue item into markdown.
  result =
    "# Merge Queue Item\n\n" &
    "**Ticket:** " & item.ticketPath & "\n" &
    "**Ticket ID:** " & item.ticketId & "\n" &
    "**Branch:** " & item.branch & "\n" &
    "**Worktree:** " & item.worktree & "\n" &
    "**Summary:** " & item.summary & "\n"

proc parseMergeQueueItem*(pendingPath: string, content: string): MergeQueueItem =
  ## Parse one merge queue item from markdown.
  result = MergeQueueItem(
    pendingPath: pendingPath,
    ticketPath: parseQueueField(content, "**Ticket:**"),
    ticketId: parseQueueField(content, "**Ticket ID:**"),
    branch: parseQueueField(content, "**Branch:**"),
    worktree: parseQueueField(content, "**Worktree:**"),
    summary: parseQueueField(content, "**Summary:**"),
  )
  if result.ticketPath.len == 0 or result.ticketId.len == 0 or result.branch.len == 0 or result.worktree.len == 0:
    raise newException(ValueError, fmt"invalid merge queue item: {pendingPath}")
