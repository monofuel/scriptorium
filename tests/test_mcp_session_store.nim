import
  std/[options, strutils, unittest],
  scriptorium/mcp_session_store

suite "scoped MCP shared bytes":
  test "snapshots and callback failures cannot mutate retained state":
    let token = "synthetic-copied-state"
    createMcpRecord(token, McpSessionRecord(descriptor: "immutable descriptor", completion: "first", methods: "[]"))
    defer: discard expireMcpRecord(token)
    var copy = readMcpRecord(token).get()
    copy.completion.add(" locally changed")
    check readMcpRecord(token).get().completion == "first"
    expect ValueError:
      updateMcpRecord(token, proc(record: var McpSessionRecord) {.gcsafe.} =
        ## Throw before publication to preserve the original shared bytes.
        record.completion = "not committed"
        raise newException(ValueError, "synthetic failure"))
    check readMcpRecord(token).get().completion == "first"

  test "expiration releases live state and rejects stale updates without touching a new token":
    createMcpRecord("old-synthetic", McpSessionRecord(completion: "old", methods: "[]"))
    check expireMcpRecord("old-synthetic").get().completion == "old"
    check readMcpRecord("old-synthetic").isNone
    createMcpRecord("new-synthetic", McpSessionRecord(completion: "new", methods: "[]"))
    defer: discard expireMcpRecord("new-synthetic")
    expect McpSessionExpiredError:
      updateMcpRecord("old-synthetic", proc(record: var McpSessionRecord) {.gcsafe.} =
        ## Attempt a stale write which must never run.
        record.completion = "forged")
    markMcpInitialized("old-synthetic")
    check not readMcpRecord("new-synthetic").get().initialized
    check readMcpRecord("new-synthetic").get().completion == "new"

  test "repeated allocation and expiration retain arbitrary exact UTF-8 bytes":
    for index in 0..<300:
      let token = "synthetic-" & $index
      let text = repeat("café 🎮 ", index mod 50)
      createMcpRecord(token, McpSessionRecord(descriptor: text, completion: text, methods: "[]"))
      check readMcpRecord(token).get().descriptor == text
      check expireMcpRecord(token).get().completion == text
      check readMcpRecord(token).isNone
      GC_fullCollect()
