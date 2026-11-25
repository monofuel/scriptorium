import
  std/[json, os, strutils, tempfiles, unicode, unittest],
  scriptorium/[agent_runner, continuation_builder, output_formatting, prompt_builders, text_encoding]

suite "UTF-8 prompt and artifact boundaries":
  test "prefixes and suffixes retain complete characters within byte budgets":
    let text = "café 🎮 漢字"
    for budget in -1..text.len + 1:
      let prefix = utf8Prefix(text, budget)
      let suffix = utf8Tail(text, budget)
      check validateUtf8(prefix) < 0
      check validateUtf8(suffix) < 0
      check prefix.len <= max(budget, 0)
      check suffix.len <= max(budget, 0)
      check text.startsWith(prefix)
      check text.endsWith(suffix)
    check utf8Tail("é" & repeat("a", 1199), 1200) == repeat("a", 1199)

  test "agent note truncation cannot poison the next ticket prompt":
    let message = "é" & repeat("a", 1199)
    let note = formatAgentRunNote("configured-model", AgentRunResult(lastMessage: message))
    check validateUtf8(note) < 0
    let prompt = buildCodingAgentPrompt("/synthetic", "/synthetic/worktree", "tickets/in-progress/0003.md", note)
    check validateUtf8(prompt) < 0
    check parseJson($( %*{"prompt": prompt}))["prompt"].getStr() == prompt

  test "malformed historical bytes are explicitly escaped only in the prompt projection":
    let directory = createTempDir("scriptorium-utf8-", "")
    defer: removeDir(directory)
    let original = "# Synthetic ticket\n\n## Agent Run\n" & "\xA9" & " retained diagnostic\n"
    let path = directory / "ticket.md"
    writeFile(path, original)
    let prompt = buildCodingAgentPrompt(directory, directory / "worktree", "tickets/in-progress/0003.md", readFile(path))
    check validateUtf8(original) >= 0
    check validateUtf8(prompt) < 0
    check "Invalid UTF-8 bytes" in prompt
    check "\\xA9 retained diagnostic" in prompt
    check readFile(path) == original
    check renderUtf8Bytes("valid café 🎮") == "valid café 🎮"
    let prediction = buildPredictionPrompt(original, "# Area", "# Spec")
    check validateUtf8(prediction) < 0

  test "continuation and visible stream clipping respect multibyte boundaries":
    let directory = createTempDir("scriptorium-utf8-rules-", "")
    defer: removeDir(directory)
    let rules = repeat("a", 3999) & "é " & repeat("b", 20)
    writeFile(directory / "AGENTS.md", rules)
    check validateUtf8(buildAgentsReinjectPrompt(directory)) < 0
    check validateUtf8(clipPlanStreamText(repeat("a", 136) & "🎮" & repeat("b", 20))) < 0
