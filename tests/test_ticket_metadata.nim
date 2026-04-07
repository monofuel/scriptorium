import
  scriptorium/ticket_metadata

proc testParseTitleStandardH1() =
  ## Verify a standard H1 line is extracted correctly.
  let content = "# Add unit tests for discord_bot.nim\n\n**Area:** notifications\n"
  let title = parseTitleFromTicketContent(content)
  doAssert title == "Add unit tests for discord_bot.nim"
  echo "[OK] parseTitleFromTicketContent: standard H1"

proc testParseTitleNoH1() =
  ## Verify empty string is returned when no H1 line exists.
  let content = "**Area:** notifications\n\nSome body text.\n"
  let title = parseTitleFromTicketContent(content)
  doAssert title == ""
  echo "[OK] parseTitleFromTicketContent: no H1"

proc testParseTitleExtraWhitespace() =
  ## Verify leading and trailing whitespace in the H1 is trimmed.
  let content = "#   Spaced out title   \n\nBody.\n"
  let title = parseTitleFromTicketContent(content)
  doAssert title == "Spaced out title"
  echo "[OK] parseTitleFromTicketContent: extra whitespace"

proc testParseTitleSkipsH2() =
  ## Verify H2 lines are not mistaken for H1.
  let content = "## Not a title\n\n# Real title\n"
  let title = parseTitleFromTicketContent(content)
  doAssert title == "Real title"
  echo "[OK] parseTitleFromTicketContent: skips H2"

proc testParseTitleFirstH1Only() =
  ## Verify only the first H1 line is used when multiple exist.
  let content = "# First title\n\n# Second title\n"
  let title = parseTitleFromTicketContent(content)
  doAssert title == "First title"
  echo "[OK] parseTitleFromTicketContent: first H1 only"

when isMainModule:
  testParseTitleStandardH1()
  testParseTitleNoH1()
  testParseTitleExtraWhitespace()
  testParseTitleSkipsH2()
  testParseTitleFirstH1Only()
