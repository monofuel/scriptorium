import
  std/[strutils, tables],
  mosty,
  scriptorium/[chat_common, git_ops, mattermost_bot, shared_state]

# -- convertPostListToTurns tests --

proc makePosts(ids: seq[string], userIds: seq[string], messages: seq[string], postTypes: seq[string] = @[]): MattermostPostList =
  ## Build a MattermostPostList from parallel sequences for testing.
  result = MattermostPostList(order: ids, posts: initTable[string, MattermostPost]())
  for i, id in ids:
    let postType = if i < postTypes.len: postTypes[i] else: ""
    result.posts[id] = MattermostPost(
      id: id,
      user_id: userIds[i],
      message: messages[i],
      post_type: postType,
    )

proc fakeUserLookup(userId: string): string =
  ## Return the userId as the username for testing.
  result = userId

proc testConvertBasic() =
  ## Verify basic conversion with filtering and chronological reversal.
  let postList = makePosts(
    @["p3", "p2", "p1"],
    @["user-a", "bot-id", "user-b"],
    @["newest", "bot reply", "oldest"],
  )
  let turns = convertPostListToTurns(postList, "bot-id", "", 10, fakeUserLookup)
  doAssert turns.len == 3
  doAssert turns[0].text == "oldest"
  doAssert turns[0].role == "user-b"
  doAssert turns[1].text == "bot reply"
  doAssert turns[1].role == "architect"
  doAssert turns[2].text == "newest"
  doAssert turns[2].role == "user-a"
  echo "[OK] convertPostListToTurns basic"

proc testConvertSkipsCurrentPost() =
  ## Verify the current post is excluded from results.
  let postList = makePosts(
    @["current", "p1"],
    @["user-a", "user-b"],
    @["skip me", "keep me"],
  )
  let turns = convertPostListToTurns(postList, "bot-id", "current", 10, fakeUserLookup)
  doAssert turns.len == 1
  doAssert turns[0].text == "keep me"
  echo "[OK] convertPostListToTurns skips current post"

proc testConvertSkipsSystemPosts() =
  ## Verify posts with non-empty post_type are skipped.
  let postList = makePosts(
    @["p2", "p1"],
    @["user-a", "user-b"],
    @["system join", "normal message"],
    @["system_join_channel", ""],
  )
  let turns = convertPostListToTurns(postList, "bot-id", "", 10, fakeUserLookup)
  doAssert turns.len == 1
  doAssert turns[0].text == "normal message"
  echo "[OK] convertPostListToTurns skips system posts"

proc testConvertSkipsEmptyMessages() =
  ## Verify posts with empty or whitespace-only messages are skipped.
  let postList = makePosts(
    @["p3", "p2", "p1"],
    @["user-a", "user-b", "user-c"],
    @["", "   ", "hello"],
  )
  let turns = convertPostListToTurns(postList, "bot-id", "", 10, fakeUserLookup)
  doAssert turns.len == 1
  doAssert turns[0].text == "hello"
  echo "[OK] convertPostListToTurns skips empty messages"

proc testConvertRespectsCountLimit() =
  ## Verify the count parameter limits the number of returned turns.
  let postList = makePosts(
    @["p4", "p3", "p2", "p1"],
    @["u1", "u2", "u3", "u4"],
    @["d", "c", "b", "a"],
  )
  let turns = convertPostListToTurns(postList, "bot-id", "", 2, fakeUserLookup)
  doAssert turns.len == 2
  # Should take first 2 from order (newest-first: p4, p3), then reverse.
  doAssert turns[0].text == "c"
  doAssert turns[1].text == "d"
  echo "[OK] convertPostListToTurns respects count limit"

proc testConvertEmptyPostList() =
  ## Verify empty post list returns empty result.
  let postList = MattermostPostList(order: @[], posts: initTable[string, MattermostPost]())
  let turns = convertPostListToTurns(postList, "bot-id", "", 10, fakeUserLookup)
  doAssert turns.len == 0
  echo "[OK] convertPostListToTurns empty post list"

proc testConvertSkipsMissingPost() =
  ## Verify posts in order but missing from posts table are skipped.
  let postList = MattermostPostList(
    order: @["missing-id", "p1"],
    posts: {"p1": MattermostPost(id: "p1", user_id: "u1", message: "hello")}.toTable,
  )
  let turns = convertPostListToTurns(postList, "bot-id", "", 10, fakeUserLookup)
  doAssert turns.len == 1
  doAssert turns[0].text == "hello"
  echo "[OK] convertPostListToTurns skips missing posts"

# -- resolveCommand tests --

proc testResolveCommandHelp() =
  ## Verify the help command returns help text.
  let response = resolveCommand("/tmp/nonexistent", PlanCallerCli, "help")
  doAssert "/status" in response
  doAssert "/help" in response
  echo "[OK] resolveCommand help"

proc testResolveCommandUnknown() =
  ## Verify unknown commands return the expected error format.
  let response = resolveCommand("/tmp/nonexistent", PlanCallerCli, "foobar")
  doAssert response == "Unknown command: !foobar"
  echo "[OK] resolveCommand unknown"

proc testResolveCommandRestart() =
  ## Verify restart returns empty string (handled separately).
  let response = resolveCommand("/tmp/nonexistent", PlanCallerCli, "restart")
  doAssert response == ""
  echo "[OK] resolveCommand restart"

# -- truncateMessage delegation tests --

proc testMattermostMessageLimit() =
  ## Verify MattermostMessageLimit is 16383.
  doAssert MattermostMessageLimit == 16383
  echo "[OK] MattermostMessageLimit is 16383"

proc testTruncateAtMattermostLimit() =
  ## Verify truncation works at the Mattermost-specific 16383 limit.
  let msg = 'x'.repeat(20000)
  let result = chat_common.truncateMessage(msg, MattermostMessageLimit)
  doAssert result.len == MattermostMessageLimit
  doAssert result.endsWith(TruncatedMarker)
  echo "[OK] truncateMessage at MattermostMessageLimit"

proc testNoTruncateUnderMattermostLimit() =
  ## Verify messages under MattermostMessageLimit are not truncated.
  let msg = 'x'.repeat(16000)
  let result = chat_common.truncateMessage(msg, MattermostMessageLimit)
  doAssert result == msg
  echo "[OK] truncateMessage under MattermostMessageLimit"

# -- Run all tests --

testConvertBasic()
testConvertSkipsCurrentPost()
testConvertSkipsSystemPosts()
testConvertSkipsEmptyMessages()
testConvertRespectsCountLimit()
testConvertEmptyPostList()
testConvertSkipsMissingPost()
testResolveCommandHelp()
testResolveCommandUnknown()
testResolveCommandRestart()
testMattermostMessageLimit()
testTruncateAtMattermostLimit()
testNoTruncateUnderMattermostLimit()
