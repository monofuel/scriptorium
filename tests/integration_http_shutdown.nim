import
  std/[httpclient, os, unittest],
  scriptorium/mcp_server

suite "MCP HTTP lifecycle":
  test "serving threads stop and release their listening sockets":
    for attempt in 0..2:
      let
        port = 34000 + (getCurrentProcessId() mod 1000)
        host = createAgentMcpHost()
      var thread: Thread[ServerThreadArgs]
      createThread(thread, runHttpServer, (host, "127.0.0.1", port))
      waitForServerReady("127.0.0.1", port)
      signalServerShutdown()
      joinThread(thread)
      let client = newHttpClient(timeout = 500)
      defer: client.close()
      expect OSError:
        discard client.getContent("http://127.0.0.1:" & $port & "/health")
