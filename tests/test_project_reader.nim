import
  std/[json, options, os, posix, strutils, tables, tempfiles, unittest],
  mcport,
  scriptorium/[git_ops, project_reader]

proc readTool(server: McpServer, name: string, arguments: JsonNode): JsonNode =
  ## Inspect the same structured result that the registered rich MCP tool returns.
  let response = server.richToolHandlers[name](arguments)
  check not response.isError
  check parseJson(response.content[0].textContent.text) == response.structuredContent.get()
  response.structuredContent.get()

suite "project-scoped read-only MCP tools":
  setup:
    let
      directory = createTempDir("scriptorium-project-read-", "")
      project = directory / "project"
      plan = directory / "plan"
    createDir(project)
    createDir(plan)
    let initialized = runCommandCapture(project, "git", @["init", "-q"])
    doAssert initialized.exitCode == 0, initialized.output
    writeFile(project / "AGENTS.md", "First line.\nSecond line.\nThird line.")
    gitRun(project, "add", "AGENTS.md")
    writeFile(plan / "spec.md", "# Actual synthetic spec\n")
    let server = newProjectReadServer(project, plan)
  teardown:
    removeDir(directory)

  test "catalog advertises only non-mutating reads and returns actual source bytes":
    check server.tools.len == 2
    for tool in server.tools.values:
      check tool.annotations.get()["readOnlyHint"].getBool()
      check not tool.annotations.get()["destructiveHint"].getBool()
      check not tool.annotations.get()["openWorldHint"].getBool()
    check readTool(server, "get_spec", %*{})["text"].getStr() == readFile(plan / "spec.md")
    let content = readTool(server, "read_project_file", %*{"path": "AGENTS.md", "line": 2, "limit": 1})
    check content["text"].getStr() == "Second line."
    check content["nextLine"].getInt() == 3

  test "untracked, private, absolute, traversing, and nonliteral paths cannot escape the scope":
    writeFile(project / "private.txt", "synthetic untracked data")
    writeFile(directory / "outside.txt", "synthetic outside data")
    writeFile(project / "*.md", "synthetic untracked wildcard")
    for path in ["private.txt", "../outside.txt", directory / "outside.txt", ".git/config",
        ".scriptorium/sessions/session.json", ".env", "*.md", ""]:
      expect ValueError:
        discard readTool(server, "read_project_file", %*{"path": path})

  test "tracked symlinks cannot read another file or directory":
    writeFile(directory / "outside.txt", "synthetic outside data")
    createSymlink(directory / "outside.txt", project / "link.txt")
    createSymlink(directory, project / "linked-directory")
    gitRun(project, "add", "link.txt", "linked-directory")
    expect OSError:
      discard readTool(server, "read_project_file", %*{"path": "link.txt"})
    removeFile(plan / "spec.md")
    createSymlink(directory / "outside.txt", plan / "spec.md")
    expect OSError:
      discard readTool(server, "get_spec", %*{})
    createDir(project / "nested")
    writeFile(project / "nested" / "notes.md", "Synthetic tracked text.")
    gitRun(project, "add", "nested/notes.md")
    moveDir(project / "nested", directory / "moved-directory")
    createSymlink(directory / "moved-directory", project / "nested")
    expect OSError:
      discard readTool(server, "read_project_file", %*{"path": "nested/notes.md"})

  test "a nonregular spec cannot block a read worker":
    removeFile(plan / "spec.md")
    doAssert mkfifo((plan / "spec.md").cstring, Mode(0o600)) == 0
    expect ValueError:
      discard readTool(server, "get_spec", %*{})

  test "non-text and oversized files fail explicitly":
    writeFile(project / "binary.txt", "synthetic\0binary")
    writeFile(project / "large.txt", repeat('x', MaxProjectTextBytes + 1))
    gitRun(project, "add", "binary.txt", "large.txt")
    for path in ["binary.txt", "large.txt"]:
      expect ValueError:
        discard readTool(server, "read_project_file", %*{"path": path})

  test "malformed inputs and invalid pagination cannot become successful reads":
    for arguments in [%*{}, %*{"path": 1}, %*{"path": "AGENTS.md", "line": 0},
        %*{"path": "AGENTS.md", "limit": 501}, %*{"path": "AGENTS.md", "limit": "all"},
        %*{"path": "AGENTS.md", "command": "cat"}]:
      expect ValueError:
        discard readTool(server, "read_project_file", arguments)
    expect ValueError:
      discard readTool(server, "get_spec", %*{"path": "outside.txt"})
