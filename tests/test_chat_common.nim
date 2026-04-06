import
  std/strutils,
  scriptorium/chat_common

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
