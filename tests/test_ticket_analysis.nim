## Unit tests for ticket analysis pure functions.

import
  std/[strutils, unittest],
  scriptorium/[prompt_builders, shared_state, ticket_analysis]

suite "parsePredictionResponse":
  test "parses valid JSON":
    let response = """{"predicted_difficulty": "medium", "predicted_duration_minutes": 30, "reasoning": "Moderate complexity."}"""
    let prediction = parsePredictionResponse(response)
    check prediction.difficulty == "medium"
    check prediction.durationMinutes == 30
    check prediction.reasoning == "Moderate complexity."

  test "handles JSON with surrounding text":
    let response = "Here is my assessment:\n{\"predicted_difficulty\": \"easy\", \"predicted_duration_minutes\": 10, \"reasoning\": \"Simple change.\"}\nDone."
    let prediction = parsePredictionResponse(response)
    check prediction.difficulty == "easy"
    check prediction.durationMinutes == 10

  test "rejects invalid difficulty":
    expect(ValueError):
      discard parsePredictionResponse("""{"predicted_difficulty": "impossible", "predicted_duration_minutes": 5, "reasoning": "test"}""")

  test "rejects missing JSON":
    expect(ValueError):
      discard parsePredictionResponse("no json here")

suite "parsePredictionFromContent":
  test "extracts prediction fields":
    let content = "# Ticket\n\n## Prediction\n- predicted_difficulty: medium\n- predicted_duration_minutes: 30\n- reasoning: Moderate.\n"
    let prediction = parsePredictionFromContent(content)
    check prediction.found == true
    check prediction.difficulty == "medium"
    check prediction.durationMinutes == 30

  test "returns not found when no prediction section":
    let content = "# Ticket\n\nSome description.\n"
    let prediction = parsePredictionFromContent(content)
    check prediction.found == false

  test "stops at next section":
    let content = "# Ticket\n\n## Prediction\n- predicted_difficulty: easy\n- predicted_duration_minutes: 10\n\n## Metrics\n- wall_time_seconds: 100\n"
    let prediction = parsePredictionFromContent(content)
    check prediction.found == true
    check prediction.difficulty == "easy"
    check prediction.durationMinutes == 10

suite "classifyActualDifficulty":
  test "returns trivial for quick single attempt done":
    check classifyActualDifficulty(1, "done", 120) == "trivial"

  test "returns easy for moderate single attempt done":
    check classifyActualDifficulty(1, "done", 600) == "easy"

  test "returns medium for long single attempt done":
    check classifyActualDifficulty(1, "done", 1200) == "medium"

  test "returns hard for two attempt done":
    check classifyActualDifficulty(2, "done", 600) == "hard"

  test "returns complex for many attempts done":
    check classifyActualDifficulty(3, "done", 600) == "complex"

  test "returns hard for reopened with few attempts":
    check classifyActualDifficulty(1, "reopened", 300) == "hard"

  test "returns complex for reopened with many attempts":
    check classifyActualDifficulty(3, "reopened", 300) == "complex"

  test "returns complex for parked":
    check classifyActualDifficulty(1, "parked", 100) == "complex"

suite "compareDifficulty":
  test "returns accurate for matching levels":
    check compareDifficulty("medium", "medium") == "accurate"

  test "returns underestimated when predicted easier":
    check compareDifficulty("easy", "hard") == "underestimated"

  test "returns overestimated when predicted harder":
    check compareDifficulty("complex", "easy") == "overestimated"

suite "runPostAnalysis":
  test "generates full analysis for ticket with prediction":
    let content = "# Ticket\n\n## Prediction\n- predicted_difficulty: easy\n- predicted_duration_minutes: 10\n- reasoning: Simple.\n\n## Metrics\n- wall_time_seconds: 1200\n- attempt_count: 2\n- outcome: done\n"
    let updated = runPostAnalysis(content, "0050", "done", 2, 1200)
    check "## Post-Analysis" in updated
    check "- actual_difficulty: hard" in updated
    check "- prediction_accuracy: underestimated" in updated
    check "- brief_summary:" in updated

  test "skips when no prediction section":
    let content = "# Ticket\n\nNo prediction here.\n"
    let updated = runPostAnalysis(content, "0051", "done", 1, 100)
    check "## Post-Analysis" notin updated
    check updated == content

suite "buildPredictionPrompt":
  test "renders template with all placeholders":
    let prompt = buildPredictionPrompt("ticket body", "area body", "spec summary")
    check "ticket body" in prompt
    check "area body" in prompt
    check "spec summary" in prompt
