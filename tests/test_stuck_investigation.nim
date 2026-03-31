## Unit tests for stuck ticket investigation functions.

import
  std/[strutils, unittest],
  scriptorium/[prompt_builders, stuck_investigation]

suite "parseInvestigationCount":
  test "returns 0 when no marker present":
    let content = "# Ticket\n\nSome content."
    check parseInvestigationCount(content) == 0

  test "returns correct value when marker present":
    let content = "# Ticket\n\n## Investigation Count: 3\n"
    check parseInvestigationCount(content) == 3

  test "returns 0 for invalid number":
    let content = "## Investigation Count: abc\n"
    check parseInvestigationCount(content) == 0

  test "returns 1 for marker with value 1":
    let content = "stuff\n## Investigation Count: 1\nmore stuff"
    check parseInvestigationCount(content) == 1

suite "setInvestigationCount":
  test "appends marker when not present":
    let content = "# Ticket\n\nSome content."
    let updated = setInvestigationCount(content, 1)
    check updated.contains("## Investigation Count: 1")
    check parseInvestigationCount(updated) == 1

  test "updates existing marker":
    let content = "# Ticket\n\n## Investigation Count: 1\n\nMore."
    let updated = setInvestigationCount(content, 2)
    check updated.contains("## Investigation Count: 2")
    check not updated.contains("## Investigation Count: 1")
    check parseInvestigationCount(updated) == 2

  test "round-trips correctly":
    let original = "# Ticket content here."
    let withCount = setInvestigationCount(original, 5)
    check parseInvestigationCount(withCount) == 5
    let updated = setInvestigationCount(withCount, 7)
    check parseInvestigationCount(updated) == 7

suite "classifyStuckFailure":
  test "detects dirty working tree":
    let content = """## Merge Queue Failure
- Failed gate: git merge master

### Quality Check Output
```
error: Your local changes to the following files would be overwritten by merge:
	docker-compose.yml
Please commit your changes or stash them before you merge.
```"""
    check classifyStuckFailure(content) == "dirty_working_tree"

  test "detects merge conflict":
    let content = """## Merge Queue Failure
- Failed gate: git merge master

### Merge Output
```
CONFLICT (content): Merge conflict in src/main.nim
Automatic merge failed; fix conflicts and then commit the result.
```"""
    check classifyStuckFailure(content) == "merge_conflict"

  test "detects test failure":
    let content = """## Merge Queue Failure
- Failed gate: make test

### Quality Check Output
```
FAIL: test_foo
```"""
    check classifyStuckFailure(content) == "test_failure"

  test "detects integration test failure":
    let content = """## Merge Queue Failure
- Failed gate: make integration-test

### Quality Check Output
```
error: timeout
```"""
    check classifyStuckFailure(content) == "test_failure"

  test "returns unknown for unrecognized patterns":
    let content = """## Merge Queue Failure
- Failed gate: something else

### Quality Check Output
```
some random error
```"""
    check classifyStuckFailure(content) == "unknown"

suite "buildInvestigateStuckPrompt":
  test "produces prompt with all placeholders resolved":
    let prompt = buildInvestigateStuckPrompt(
      "/repo",
      "# Ticket 0077\nSome content.",
      "dirty_working_tree",
      "M docker-compose.yml",
      "abc1234 last commit",
    )
    check prompt.contains("/repo")
    check prompt.contains("# Ticket 0077")
    check prompt.contains("dirty_working_tree")
    check prompt.contains("M docker-compose.yml")
    check prompt.contains("abc1234 last commit")
    check not prompt.contains("{{")
