import
  std/[strformat, strutils]

const
  PromptDirectory = "prompts/"
  CodingAgentTemplate* = staticRead(PromptDirectory & "coding_agent.md")
  ArchitectAreasTemplate* = staticRead(PromptDirectory & "architect_areas.md")
  ManagerTicketsTemplate* = staticRead(PromptDirectory & "manager_tickets.md")
  PlanScopeTemplate* = staticRead(PromptDirectory & "plan_scope.md")
  ArchitectPlanOneShotTemplate* = staticRead(PromptDirectory & "architect_plan_oneshot.md")
  ArchitectPlanInteractiveTemplate* = staticRead(PromptDirectory & "architect_plan_interactive.md")
  CodexRetryContinuationTemplate* = staticRead(PromptDirectory & "codex_retry_continuation.md")
  CodexRetryDefaultContinuationText* = staticRead(PromptDirectory & "codex_retry_default_continuation.md")
  ArchitectAskInteractiveTemplate* = staticRead(PromptDirectory & "architect_ask_interactive.md")
  TicketPredictionTemplate* = staticRead(PromptDirectory & "ticket_prediction.md")
  ReviewAgentTemplate* = staticRead(PromptDirectory & "review_agent.md")
  AgentsExampleTemplate* = staticRead(PromptDirectory & "agents_example.md")
  AuditAgentTemplate* = staticRead(PromptDirectory & "audit_agent.md")
  ArchitectDoTemplate* = staticRead(PromptDirectory & "architect_do.md")
  ArchitectInvestigateStuckTemplate* = staticRead(PromptDirectory & "architect_investigate_stuck.md")
  ToneTemplate* = staticRead(PromptDirectory & "tone.md")

type
  PromptBinding* = tuple[name: string, value: string]

proc markerForPlaceholder(name: string): string =
  ## Return one placeholder marker for the provided placeholder name.
  let clean = name.strip()
  if clean.len == 0:
    raise newException(ValueError, "placeholder name cannot be empty")
  result = "{{" & clean & "}}"

proc unresolvedPlaceholder(value: string): string =
  ## Return one unresolved placeholder marker when present.
  let startIndex = value.find("{{")
  if startIndex < 0:
    return ""

  let endIndex = value.find("}}", startIndex + 2)
  if endIndex < 0:
    result = value[startIndex..^1]
  else:
    result = value[startIndex..(endIndex + 1)]

proc renderPromptTemplate*(templateText: string, bindings: openArray[PromptBinding]): string =
  ## Render one prompt template with required placeholder bindings.
  ## Binding values may contain literal ``{{`` sequences (e.g. code diffs)
  ## so we validate unresolved placeholders *before* substitution, not after.
  if templateText.strip().len == 0:
    raise newException(ValueError, "prompt template cannot be empty")

  # First pass: verify all expected placeholders exist in the template.
  var remainingTemplate = templateText
  for binding in bindings:
    let marker = markerForPlaceholder(binding.name)
    if remainingTemplate.find(marker) < 0:
      raise newException(ValueError, &"prompt template is missing placeholder: {marker}")
    remainingTemplate = remainingTemplate.replace(marker, "")

  # Check for unresolved placeholders in the template (with values stripped out).
  let unresolved = unresolvedPlaceholder(remainingTemplate)
  if unresolved.len > 0:
    raise newException(ValueError, &"prompt template has unresolved placeholder: {unresolved}")

  # Second pass: actually substitute the values.
  result = templateText
  for binding in bindings:
    let marker = markerForPlaceholder(binding.name)
    result = result.replace(marker, binding.value)
