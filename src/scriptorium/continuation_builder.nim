import
  std/os

const
  AgentsFileName = "AGENTS.md"
  MaxAgentsFileChars = 4000
  DefaultContinuationText = "Continue from the previous attempt and complete the ticket. When done, call the `submit_pr` MCP tool with a summary."

proc buildAgentsReinjectPrompt*(workingDir: string): string =
  ## Build a continuation prompt that re-injects AGENTS.md project rules.
  ## Falls back to the default continuation text if AGENTS.md is not found.
  var agentsPath = workingDir / AgentsFileName
  if not fileExists(agentsPath):
    let parentPath = parentDir(workingDir) / AgentsFileName
    if fileExists(parentPath):
      agentsPath = parentPath
    else:
      return DefaultContinuationText

  var content = readFile(agentsPath)
  if content.len > MaxAgentsFileChars:
    content = content[0..<MaxAgentsFileChars] & "\n\n(Rules truncated due to length.)"

  result = "The following project rules from AGENTS.md must be followed:\n\n" &
    content & "\n\n" & DefaultContinuationText
