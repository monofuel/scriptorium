import
  std/[strformat, strutils],
  ./[agent_runner, prompt_catalog, shared_state, ticket_metadata]

const
  PlanStreamPreviewChars* = 140
  StallContinuationText* = "The previous attempt exited cleanly without calling the `submit_pr` MCP tool.\nThis is a stall — the agent exited without completing the ticket.\nContinue working on the ticket and call `submit_pr` with a summary when done."
  StallTestOutputMaxBytes* = 8192

proc truncateTail*(value: string, maxChars: int): string =
  ## Return at most maxChars from the end of value.
  if maxChars < 1:
    result = ""
  elif value.len <= maxChars:
    result = value
  else:
    result = value[(value.len - maxChars)..^1]

proc clipPlanStreamText*(value: string): string =
  ## Clip one stream message for concise interactive status rendering.
  let normalized = value.replace('\n', ' ').replace('\r', ' ').strip()
  if normalized.len <= PlanStreamPreviewChars:
    result = normalized
  elif PlanStreamPreviewChars > 3:
    result = normalized[0..<(PlanStreamPreviewChars - 3)] & "..."
  else:
    result = normalized

proc formatPlanStreamEvent*(event: AgentStreamEvent): string =
  ## Format one agent stream event for interactive planning output.
  let text = clipPlanStreamText(event.text)
  case event.kind
  of agentEventHeartbeat:
    result = "[thinking] still working..."
  of agentEventReasoning:
    if text.len > 0:
      result = "[thinking] " & text
    else:
      result = "[thinking]"
  of agentEventTool:
    if text.len > 0:
      result = "[tool] " & text
    else:
      result = "[tool]"
  of agentEventStatus:
    if text.len > 0:
      result = "[status] " & text
    else:
      result = ""
  of agentEventMessage:
    result = ""

proc buildCodingAgentPrompt*(repoPath: string, worktreePath: string, ticketRelPath: string, ticketContent: string, priorWorkNote: string = ""): string =
  ## Build the coding-agent prompt from ticket context.
  ## When priorWorkNote is non-empty, it is appended to inform the agent of existing commits.
  result = renderPromptTemplate(
    CodingAgentTemplate,
    [
      (name: "PROJECT_REPO_PATH", value: repoPath),
      (name: "WORKTREE_PATH", value: worktreePath),
      (name: "TICKET_PATH", value: ticketRelPath),
      (name: "TICKET_CONTENT", value: ticketContent.strip()),
    ],
  )
  if priorWorkNote.len > 0:
    result = result.strip() & "\n\n" & priorWorkNote

proc buildStallContinuationPrompt*(initialPrompt: string, ticketContent: string, ticketId: string, attempt: int, testExitCode: int, testOutput: string): string =
  ## Build a continuation prompt for a coding agent that stalled without calling submit_pr.
  ## Includes test results: pass/fail status and output from `make test`.
  let testSection =
    if testExitCode == 0:
      "## Test Results\n\nTests are passing (`make test` exited 0). Continue working on the ticket and call `submit_pr` when done."
    else:
      let truncated = truncateTail(testOutput.strip(), StallTestOutputMaxBytes)
      "## Test Results\n\nTests are FAILING (`make test` exited " & $testExitCode & "). Fix the failing tests before submitting.\n\n```\n" & truncated & "\n```"
  result = initialPrompt.strip() & "\n\n" &
    fmt"This is stall retry attempt {attempt} for ticket {ticketId}. " &
    "The previous attempt exited cleanly without calling the `submit_pr` MCP tool.\n\n" &
    "Ticket content:\n\n" & ticketContent.strip() & "\n\n" &
    StallContinuationText & "\n\n" &
    testSection

proc buildReviewAgentPrompt*(ticketContent: string, diffContent: string, areaContent: string, submitSummary: string, agentsContent: string, specContent: string): string =
  ## Build the review agent prompt from ticket, diff, area, summary, AGENTS.md, and spec context.
  result = renderPromptTemplate(
    ReviewAgentTemplate,
    [
      (name: "TICKET_CONTENT", value: ticketContent.strip()),
      (name: "DIFF_CONTENT", value: diffContent.strip()),
      (name: "AREA_CONTENT", value: areaContent.strip()),
      (name: "AGENTS_CONTENT", value: agentsContent.strip()),
      (name: "SPEC_CONTENT", value: specContent.strip()),
      (name: "SUBMIT_SUMMARY", value: submitSummary.strip()),
    ],
  )

proc buildArchitectAreasPrompt*(repoPath: string, planPath: string, spec: string): string =
  ## Build the architect prompt that writes area files directly into areas/.
  result = renderPromptTemplate(
    ArchitectAreasTemplate,
    [
      (name: "PROJECT_REPO_PATH", value: repoPath),
      (name: "WORKTREE_PATH", value: planPath),
      (name: "CURRENT_SPEC", value: spec.strip()),
    ],
  )

proc buildManagerTicketsPrompt*(repoPath: string,
    areaId: string, areaRelPath: string, areaContent: string, nextId: int): string =
  ## Build a single-area manager prompt using the ManagerTicketsTemplate.
  let startIdText = &"{nextId:04d}"
  result = renderPromptTemplate(
    ManagerTicketsTemplate,
    [
      (name: "PROJECT_REPO_PATH", value: repoPath),
      (name: "NEXT_ID", value: startIdText),
      (name: "AREA_FIELD_PREFIX", value: AreaFieldPrefix),
      (name: "AREA_ID", value: areaId),
      (name: "AREA_PATH", value: areaRelPath),
      (name: "AREA_CONTENT", value: areaContent.strip()),
    ],
  )

proc buildPredictionPrompt*(ticketContent: string, areaContent: string, specSummary: string): string =
  ## Build the prediction prompt from ticket, area, and spec context.
  result = renderPromptTemplate(
    TicketPredictionTemplate,
    [
      (name: "TICKET_CONTENT", value: ticketContent.strip()),
      (name: "AREA_CONTENT", value: areaContent.strip()),
      (name: "SPEC_SUMMARY", value: specSummary.strip()),
    ],
  )

proc buildPlanScopePrompt*(repoPath: string, planPath: string): string =
  ## Build shared planning prompt context with read and write scope.
  result = renderPromptTemplate(
    PlanScopeTemplate,
    [
      (name: "PROJECT_REPO_PATH", value: repoPath),
      (name: "WORKTREE_PATH", value: planPath),
    ],
  )

proc buildArchitectPlanPrompt*(repoPath: string, planPath: string, userPrompt: string, currentSpec: string): string =
  ## Build the one-shot architect prompt that edits spec.md in place.
  result = renderPromptTemplate(
    ArchitectPlanOneShotTemplate,
    [
      (name: "PLAN_SCOPE", value: buildPlanScopePrompt(repoPath, planPath).strip()),
      (name: "USER_REQUEST", value: userPrompt.strip()),
      (name: "CURRENT_SPEC", value: currentSpec.strip()),
    ],
  )

proc buildInteractivePlanPrompt*(repoPath: string, planPath: string, spec: string, history: seq[PlanTurn], userMsg: string): string =
  ## Assemble the multi-turn architect prompt with spec, history, and current message.
  var conversationHistory = ""
  if history.len > 0:
    conversationHistory = "\nConversation history:\n"
    for turn in history:
      conversationHistory &= fmt"\n[{turn.role}]: {turn.text.strip()}\n"

  result = renderPromptTemplate(
    ArchitectPlanInteractiveTemplate,
    [
      (name: "PLAN_SCOPE", value: buildPlanScopePrompt(repoPath, planPath).strip()),
      (name: "CURRENT_SPEC", value: spec.strip()),
      (name: "CONVERSATION_HISTORY", value: conversationHistory),
      (name: "USER_MESSAGE", value: userMsg.strip()),
    ],
  )

proc buildInteractiveAskPrompt*(repoPath: string, planPath: string, spec: string, history: seq[PlanTurn], userMsg: string): string =
  ## Assemble the multi-turn read-only architect prompt with spec, history, and current message.
  var conversationHistory = ""
  if history.len > 0:
    conversationHistory = "\nConversation history:\n"
    for turn in history:
      conversationHistory &= fmt"\n[{turn.role}]: {turn.text.strip()}\n"

  result = renderPromptTemplate(
    ArchitectAskInteractiveTemplate,
    [
      (name: "PLAN_SCOPE", value: buildPlanScopePrompt(repoPath, planPath).strip()),
      (name: "CURRENT_SPEC", value: spec.strip()),
      (name: "CONVERSATION_HISTORY", value: conversationHistory),
      (name: "USER_MESSAGE", value: userMsg.strip()),
    ],
  )
