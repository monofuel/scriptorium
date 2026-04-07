import
  std/[os, strutils, tempfiles],
  scriptorium/[chat_common, git_ops, pause_flag]

proc testParseChatModeAsk() =
  ## Verify "ask:" prefix parses to chatModeAsk with explicit=true.
  let (mode, text, explicit) = parseChatMode("ask: what is this?")
  doAssert mode == chatModeAsk
  doAssert text == "what is this?"
  doAssert explicit == true
  echo "[OK] parseChatMode ask prefix"

proc testParseChatModePlan() =
  ## Verify "plan:" prefix parses to chatModePlan with explicit=true.
  let (mode, text, explicit) = parseChatMode("plan: build a feature")
  doAssert mode == chatModePlan
  doAssert text == "build a feature"
  doAssert explicit == true
  echo "[OK] parseChatMode plan prefix"

proc testParseChatModeDo() =
  ## Verify "do:" prefix parses to chatModeDo with explicit=true.
  let (mode, text, explicit) = parseChatMode("do: run the thing")
  doAssert mode == chatModeDo
  doAssert text == "run the thing"
  doAssert explicit == true
  echo "[OK] parseChatMode do prefix"

proc testParseChatModeDefault() =
  ## Verify no prefix defaults to chatModePlan with explicit=false.
  let (mode, text, explicit) = parseChatMode("just a message")
  doAssert mode == chatModePlan
  doAssert text == "just a message"
  doAssert explicit == false
  echo "[OK] parseChatMode default (no prefix)"

proc testParseChatModeCaseInsensitive() =
  ## Verify prefix matching is case insensitive.
  let (mode1, text1, explicit1) = parseChatMode("ASK: upper case")
  doAssert mode1 == chatModeAsk
  doAssert text1 == "upper case"
  doAssert explicit1 == true

  let (mode2, text2, explicit2) = parseChatMode("Do: mixed case")
  doAssert mode2 == chatModeDo
  doAssert text2 == "mixed case"
  doAssert explicit2 == true

  let (mode3, text3, explicit3) = parseChatMode("PLAN: all caps")
  doAssert mode3 == chatModePlan
  doAssert text3 == "all caps"
  doAssert explicit3 == true
  echo "[OK] parseChatMode case insensitive"

proc testParseChatModeWhitespace() =
  ## Verify leading and trailing whitespace is handled.
  let (mode, text, explicit) = parseChatMode("  ask:  hello world  ")
  doAssert mode == chatModeAsk
  doAssert text == "hello world"
  doAssert explicit == true
  echo "[OK] parseChatMode whitespace handling"

proc testChatModeEnumValues() =
  ## Verify all ChatMode enum values exist.
  doAssert chatModePlan != chatModeAsk
  doAssert chatModeChat != chatModeIgnore
  doAssert chatModeDo != chatModeChat
  echo "[OK] ChatMode enum values"

proc testTruncateMessageUnderLimit() =
  ## Verify messages under the limit are returned unchanged.
  let msg = "short message"
  let result = truncateMessage(msg, 2000)
  doAssert result == msg
  echo "[OK] truncateMessage under limit"

proc testTruncateMessageAtLimit() =
  ## Verify messages exactly at the limit are returned unchanged.
  let msg = 'x'.repeat(2000)
  let result = truncateMessage(msg, 2000)
  doAssert result == msg
  doAssert result.len == 2000
  echo "[OK] truncateMessage at limit"

proc testTruncateMessageOverLimit() =
  ## Verify messages over the limit are truncated with marker.
  let msg = 'x'.repeat(3000)
  let result = truncateMessage(msg, 2000)
  doAssert result.len == 2000
  doAssert result.endsWith(TruncatedMarker)
  echo "[OK] truncateMessage over limit"

proc testTruncateMessageCustomLimit() =
  ## Verify truncation works with a custom limit (e.g. Mattermost 16383).
  let msg = 'y'.repeat(20000)
  let result = truncateMessage(msg, 16383)
  doAssert result.len == 16383
  doAssert result.endsWith(TruncatedMarker)
  echo "[OK] truncateMessage custom limit"

proc testHandleHelp() =
  ## Verify handleHelp returns a message containing all commands.
  let result = handleHelp()
  doAssert "/status" in result
  doAssert "/queue" in result
  doAssert "/pause" in result
  doAssert "/resume" in result
  doAssert "/help" in result
  doAssert "/restart" in result
  doAssert "ask:" in result
  doAssert "plan:" in result
  doAssert "do:" in result
  echo "[OK] handleHelp contains all commands"

proc testHandlePauseNotPaused() =
  ## Verify handlePause writes the flag and returns confirmation.
  let tmp = createTempDir("chat_pause_", "", getTempDir())
  defer: removeDir(tmp)
  createDir(tmp / ManagedStateDirName)

  let result = handlePause(tmp)
  doAssert "paused" in result.toLowerAscii()
  doAssert isPaused(tmp)
  echo "[OK] handlePause when not paused"

proc testHandlePauseAlreadyPaused() =
  ## Verify handlePause returns already-paused message when flag exists.
  let tmp = createTempDir("chat_pause_already_", "", getTempDir())
  defer: removeDir(tmp)
  createDir(tmp / ManagedStateDirName)

  writePauseFlag(tmp)
  let result = handlePause(tmp)
  doAssert "already paused" in result.toLowerAscii()
  doAssert isPaused(tmp)
  echo "[OK] handlePause when already paused"

proc testHandleResumeWhenPaused() =
  ## Verify handleResume removes the flag and returns confirmation.
  let tmp = createTempDir("chat_resume_", "", getTempDir())
  defer: removeDir(tmp)
  createDir(tmp / ManagedStateDirName)

  writePauseFlag(tmp)
  let result = handleResume(tmp)
  doAssert "resumed" in result.toLowerAscii()
  doAssert not isPaused(tmp)
  echo "[OK] handleResume when paused"

proc testHandleResumeWhenNotPaused() =
  ## Verify handleResume returns not-paused message when no flag exists.
  let tmp = createTempDir("chat_resume_noop_", "", getTempDir())
  defer: removeDir(tmp)
  createDir(tmp / ManagedStateDirName)

  let result = handleResume(tmp)
  doAssert "was not paused" in result.toLowerAscii()
  doAssert not isPaused(tmp)
  echo "[OK] handleResume when not paused"

proc testTruncateMessageWithSpecNote() =
  ## Verify that response + spec note is properly truncated when combined length exceeds limit.
  let specNote = "\n[spec.md updated]"
  let longResponse = 'x'.repeat(1995) & specNote
  let result = truncateMessage(longResponse, 2000)
  doAssert result.len == 2000
  doAssert result.endsWith(TruncatedMarker)
  echo "[OK] truncateMessage with spec note over limit"

proc testTruncateMessageWithSpecNoteUnderLimit() =
  ## Verify that response + spec note is preserved when combined length is under limit.
  let specNote = "\n[spec.md updated]"
  let shortResponse = "Spec updated." & specNote
  let result = truncateMessage(shortResponse, 2000)
  doAssert result == shortResponse
  doAssert result.endsWith(specNote)
  echo "[OK] truncateMessage with spec note under limit"

testParseChatModeAsk()
testParseChatModePlan()
testParseChatModeDo()
testParseChatModeDefault()
testParseChatModeCaseInsensitive()
testParseChatModeWhitespace()
testChatModeEnumValues()
testTruncateMessageUnderLimit()
testTruncateMessageAtLimit()
testTruncateMessageOverLimit()
testTruncateMessageCustomLimit()
testHandleHelp()
testHandlePauseNotPaused()
testHandlePauseAlreadyPaused()
testHandleResumeWhenPaused()
testHandleResumeWhenNotPaused()
testTruncateMessageWithSpecNote()
testTruncateMessageWithSpecNoteUnderLimit()
