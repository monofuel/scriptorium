import
  std/strutils,
  scriptorium/[chat_common, discord_bot]

proc testTrackMessageIdNew() =
  ## Verify that a new message ID is accepted.
  resetDedup()
  doAssert trackMessageId("msg-1") == true
  echo "[OK] trackMessageId accepts new ID"

proc testTrackMessageIdDuplicate() =
  ## Verify that a duplicate message ID is rejected.
  resetDedup()
  doAssert trackMessageId("msg-1") == true
  doAssert trackMessageId("msg-1") == false
  echo "[OK] trackMessageId rejects duplicate ID"

proc testTrackMessageIdEviction() =
  ## Verify that oldest IDs are evicted after MaxProcessedMessageIds.
  resetDedup()
  for i in 0 ..< MaxProcessedMessageIds:
    let id = "msg-" & $i
    doAssert trackMessageId(id) == true
  # All 500 slots are full. Adding one more evicts the oldest (msg-0).
  doAssert trackMessageId("msg-new") == true
  # msg-0 was evicted, so it should be accepted again.
  doAssert trackMessageId("msg-0") == true
  # msg-2 is still in the set (msg-1 was evicted when msg-0 was re-added).
  doAssert trackMessageId("msg-2") == false
  echo "[OK] trackMessageId evicts oldest after cap"

proc testTrackMessageIdReAdd() =
  ## Verify that a previously-evicted ID can be re-added.
  resetDedup()
  for i in 0 ..< MaxProcessedMessageIds + 1:
    discard trackMessageId("id-" & $i)
  # id-0 was evicted by the +1 insertion.
  doAssert trackMessageId("id-0") == true
  # Now id-0 is tracked again, so duplicate check should reject it.
  doAssert trackMessageId("id-0") == false
  echo "[OK] trackMessageId re-adds evicted ID"

proc testTruncateMessageUnderLimit() =
  ## Verify messages under the Discord limit are returned unchanged.
  let msg = "short message"
  let result = truncateMessage(msg)
  doAssert result == msg
  echo "[OK] discord truncateMessage under limit"

proc testTruncateMessageAtLimit() =
  ## Verify messages exactly at the Discord limit are returned unchanged.
  let msg = 'x'.repeat(DiscordMessageLimit)
  let result = truncateMessage(msg)
  doAssert result == msg
  doAssert result.len == DiscordMessageLimit
  echo "[OK] discord truncateMessage at limit"

proc testTruncateMessageOverLimit() =
  ## Verify messages over the Discord limit are truncated with marker.
  let msg = 'x'.repeat(DiscordMessageLimit + 500)
  let result = truncateMessage(msg)
  doAssert result.len == DiscordMessageLimit
  doAssert result.endsWith(TruncatedMarker)
  echo "[OK] discord truncateMessage over limit"

proc testIsUserAllowedNoAllowlist() =
  ## Verify all users pass when no allowlist is configured.
  doAssert isUserAllowed("123", "alice", @[], @[]) == true
  echo "[OK] isUserAllowed passes with no allowlist"

proc testIsUserAllowedByUserId() =
  ## Verify a user matching allowedUserIds is allowed.
  doAssert isUserAllowed("123", "alice", @["123", "456"], @[]) == true
  echo "[OK] isUserAllowed passes by userId"

proc testIsUserAllowedByUsername() =
  ## Verify a user matching allowedUsers is allowed even without matching userId.
  doAssert isUserAllowed("999", "alice", @["123"], @["alice", "bob"]) == true
  echo "[OK] isUserAllowed passes by username"

proc testIsUserAllowedByUsernameOnly() =
  ## Verify a user matching allowedUsers is allowed when allowedUserIds is empty.
  doAssert isUserAllowed("999", "alice", @[], @["alice"]) == true
  echo "[OK] isUserAllowed passes by username only"

proc testIsUserAllowedRejected() =
  ## Verify a user matching neither list is rejected.
  doAssert isUserAllowed("999", "charlie", @["123"], @["alice"]) == false
  echo "[OK] isUserAllowed rejects non-matching user"

proc testIsUserAllowedEmptyUsername() =
  ## Verify that an empty username does not match allowedUsers entries.
  doAssert isUserAllowed("999", "", @["123"], @["alice"]) == false
  echo "[OK] isUserAllowed rejects empty username"

initDedup()
testTrackMessageIdNew()
testTrackMessageIdDuplicate()
testTrackMessageIdEviction()
testTrackMessageIdReAdd()
testTruncateMessageUnderLimit()
testTruncateMessageAtLimit()
testTruncateMessageOverLimit()
testIsUserAllowedNoAllowlist()
testIsUserAllowedByUserId()
testIsUserAllowedByUsername()
testIsUserAllowedByUsernameOnly()
testIsUserAllowedRejected()
testIsUserAllowedEmptyUsername()
