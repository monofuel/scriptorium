import
  std/[json, sets, strformat, strutils],
  ./[logging, output_formatting, shared_state, ticket_metadata]

proc dependenciesSatisfied*(ticketContent: string, doneIds: HashSet[string]): bool =
  ## Check whether all declared dependencies are in the done set.
  let deps = parseDependsFromTicketContent(ticketContent)
  if deps.len == 0:
    return true
  for dep in deps:
    if dep notin doneIds:
      return false
  return true

proc parsePredictionResponse*(response: string): TicketPrediction =
  ## Parse a JSON prediction response from the model into a TicketPrediction.
  let trimmed = response.strip()
  # Find JSON object in response (skip any surrounding text or markdown fences).
  var jsonStart = trimmed.find('{')
  var jsonEnd = trimmed.rfind('}')
  if jsonStart < 0 or jsonEnd < 0 or jsonEnd <= jsonStart:
    raise newException(ValueError, "no JSON object found in prediction response")
  let jsonStr = trimmed[jsonStart..jsonEnd]
  let node = parseJson(jsonStr)
  let difficulty = node.getOrDefault("predicted_difficulty").getStr("")
  if difficulty notin ValidDifficulties:
    raise newException(ValueError, "invalid predicted_difficulty: " & difficulty)
  let durationMinutes = node.getOrDefault("predicted_duration_minutes").getInt(0)
  let reasoning = node.getOrDefault("reasoning").getStr("")
  result = TicketPrediction(
    difficulty: difficulty,
    durationMinutes: durationMinutes,
    reasoning: reasoning,
  )

proc parsePredictionFromContent*(content: string): tuple[found: bool, difficulty: string, durationMinutes: int] =
  ## Extract predicted difficulty and duration from a ticket's Prediction section.
  let marker = "## Prediction"
  let idx = content.find(marker)
  if idx < 0:
    return (found: false, difficulty: "", durationMinutes: 0)
  let section = content[idx .. ^1]
  var difficulty = ""
  var durationMinutes = 0
  for line in section.splitLines():
    if line.startsWith("## ") and line != marker:
      break
    if line.startsWith("- predicted_difficulty: "):
      difficulty = line["- predicted_difficulty: ".len .. ^1].strip()
    elif line.startsWith("- predicted_duration_minutes: "):
      let valStr = line["- predicted_duration_minutes: ".len .. ^1].strip()
      durationMinutes = parseInt(valStr)
  if difficulty.len == 0:
    return (found: false, difficulty: "", durationMinutes: 0)
  result = (found: true, difficulty: difficulty, durationMinutes: durationMinutes)

proc classifyActualDifficulty*(attemptCount: int, outcome: string, wallTimeSeconds: int): string =
  ## Classify actual difficulty based on attempt count, outcome, and wall time.
  if outcome == "parked":
    return "complex"
  if outcome == "reopened":
    if attemptCount >= 3:
      return "complex"
    return "hard"
  # outcome == "done"
  if attemptCount == 1 and wallTimeSeconds < 300:
    return "trivial"
  if attemptCount == 1 and wallTimeSeconds < 900:
    return "easy"
  if attemptCount == 1:
    return "medium"
  if attemptCount == 2:
    return "hard"
  return "complex"

proc compareDifficulty*(predicted: string, actual: string): string =
  ## Compare predicted vs actual difficulty and return accuracy label.
  let levels = @["trivial", "easy", "medium", "hard", "complex"]
  let predIdx = levels.find(predicted)
  let actIdx = levels.find(actual)
  if predIdx < 0 or actIdx < 0:
    return "accurate"
  if predIdx == actIdx:
    return "accurate"
  if predIdx < actIdx:
    return "underestimated"
  return "overestimated"

proc runPostAnalysis*(ticketContent: string, ticketId: string, outcome: string, attemptCount: int, wallTimeSeconds: int): string =
  ## Run post-analysis comparing predicted vs actual metrics. Returns updated content.
  ## If no prediction section exists, returns the original content unchanged.
  let prediction = parsePredictionFromContent(ticketContent)
  if not prediction.found:
    logInfo(&"ticket {ticketId}: post-analysis skipped (no prediction section)")
    return ticketContent
  let actualDifficulty = classifyActualDifficulty(attemptCount, outcome, wallTimeSeconds)
  let predictionAccuracy = compareDifficulty(prediction.difficulty, actualDifficulty)
  let wallDuration = formatDuration(float(wallTimeSeconds))
  let briefSummary = &"Predicted {prediction.difficulty}, actual was {actualDifficulty} with {attemptCount} attempt(s) in {wallDuration}."
  logInfo(&"ticket {ticketId}: post-analysis: predicted={prediction.difficulty} actual={actualDifficulty} accuracy={predictionAccuracy} wall={wallDuration}")
  result = appendPostAnalysisNote(ticketContent, actualDifficulty, predictionAccuracy, briefSummary)
