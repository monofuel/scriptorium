# scriptorium

- agentic coding orchestrator

## Running

### Development (Nim)

Run any scriptorium command directly with Nim:
```
nim r src/scriptorium.nim <command>
```

Examples:
```
nim r src/scriptorium.nim plan        # interactive planning session
nim r src/scriptorium.nim run         # start the orchestrator
nim r src/scriptorium.nim status      # check orchestrator status
```

### Docker Compose

```
docker-compose up --build
```

This mounts the current directory as `/workspace`, passes through `~/.codex` and `~/.claude` credentials, and runs the orchestrator. Set `OPENAI_API_KEY` or `CODEX_API_KEY` environment variables as needed.

the docker build is ONLY needed to update the scriptorium binary. the entire git folder is passed in through a docker compose volume, so it can run directly against our git repo (including .git).

To build the Docker image separately:
```
make docker-build
```

## Dependencies

- Nim >= 2.0.0
- nimby for dependency management (not nimble)
- jsony, mummy, mcport

## Tests

- Run `make test` to run local unit tests (`tests/test_*.nim`)
- Run `make integration-test` to run integration tests (`tests/integration_*.nim`) that may call real external services/tools (for example Codex)
- Individual test files can be run with `nim r tests/test_scriptorium.nim`
- `tests/config.nims` contains `--path:"../src"` so tests can import project modules directly

### Unit tests vs integration tests

**Unit tests** (`tests/test_*.nim`) test individual functions and modules in isolation.
Mocks and fakes belong here. If you are replacing a real dependency with a fake one, that is a unit test.

**Integration tests** (`tests/integration_*.nim`) test that real components work together.
Integration tests call real binaries, real APIs, and real services. They do NOT use mocks or fakes.
The whole point of an integration test is to verify that the actual pieces fit together correctly.
If you mock the thing you are integrating with, you are not testing integration — you are writing a unit test with extra steps.

Rules:
- If it uses a mock, fake, or stub for a core dependency, it is a unit test. Put it in `tests/test_*.nim`.
- If it calls a real external tool or service (Codex, git, an HTTP API), it is an integration test. Put it in `tests/integration_*.nim`.
- Do not put mocked tests in integration test files. Do not call real services in unit test files.
- Integration tests may be slow, flaky, or require credentials. That is expected and fine.

## project best practices

- stick to minimal dependencies.
  - prefer dependencies from monofuel, treeform, and guzba.
- stick to nim for programming.
- organize commands with a Makefile to make projects easy to automate.

- we should NEVER rely on stdout scanning.
- we should rely on proper reliable mcp tools whenever agents need to interact.
- integration tests should properly test the full integration, do not mock things out, do not skip, do not use fakes.
- when testing, do not rely on env flags to toggle categories or skipping tests or any shenanigans. test the thing properly. if it fails, fail fast and fail loudly so it can be fixed.

- be patient
- make sure to fully solve problems and fix the root cause.
  - if you don't fully solve an issue, it will come back over and over again until it is fixed.
- avoid playing "whack a mole" with surface level issues. think through the problem and fix the root cause if possible. if fixing the root cause is not possible, leave comments documenting the issue.

## Checking the spec

The spec on the `scriptorium/plan` branch can be very large (70KB+, 40+ sections). When checking whether specific content exists in the spec, always search with `grep` rather than reading only the first N lines. Using `head` or reading a small offset will miss content further down the file and lead to incorrect conclusions about what the spec contains.

```
git show scriptorium/plan:spec.md | grep -i "keyword"
```

## MCP transport

- MCPort uses plain JSON-RPC over HTTP POST (Streamable HTTP). It does NOT support SSE (Server-Sent Events).
- mummy (the HTTP server MCPort uses) does not support SSE, and SSE is not planned.
- when configuring MCP server connections for agent harnesses, do NOT set `"type": "sse"`. Either omit the type field or use `"streamable-http"` / `"http"` depending on what the client expects.
- codex uses `-c mcp_servers.<name>.url=...` with separate `-c` flags for each field. Do NOT use the table/JSON syntax — codex does not parse it correctly.

## Agent completion protocol

- coding agents must call the `submit_pr` MCP tool when ticket work is complete.
- include a short `summary` argument describing the completed changes.
- orchestrator merge-queue enqueueing must use MCP tool state, not stdout parsing.

## Nim

## Nim best practices

**Prefer letting errors bubble up naturally** - Nim's stack traces are excellent for debugging:

Default approach - let operations fail with full context:
```nim
# Simple and clear - if writeFile fails, we get a full stack trace
writeFile(filepath, content)

# Database operations - let them fail with complete error information
db.exec(sql"INSERT INTO users (name) VALUES (?)", username)
```

For validation and early returns, check conditions explicitly:
```nim
# Check preconditions and exit early with clear messages
if not fileExists(parentDir):
  error "Parent directory does not exist"
  quit(1)

if username.len == 0:
  error "Username cannot be empty"
  quit(1)

# Now proceed with the operation
writeFile(filepath, content)
```

This approach ensures full stack traces in CI environments and makes debugging straightforward.

- format strings with & are preferred over fmt.
- also, avoid calling functions inside of format strings as this can be confusing and error prone.
- assigning to variables and then using them in the format string is easier to read and debug.
```nim
let
  name = "monofuel"
  scores = [100, 200, 300]
  scoreString = scores.join(", ")
echo &"Hello, {name}! You have {scoreString} points."
```


### Nim Imports

One `import` block. Use bracket syntax. Order: std/ then libraries then local. No quotes on paths.

WRONG:
```nim
import std/os
import std/strutils
import jsony
import ./models
```

RIGHT:
```nim
import
  std/[os, strutils],
  jsony,
  ./[models, logs]
```

### Nim Procs

- do not use forward declarations. If a proc is called before it is defined, move the proc definition above the call site instead.
- do not put comments before functions! comments go inside functions.
- every proc should have a nimdoc comment
- nimdoc comments start with ##
- nimdoc comments should be complete sentences followed by punctuation
for example,
```
proc sumOfMultiples(limit: int): int =
  ## Calculate the sum of all multiples of 3 or 5 below the limit.
  var total = 0
  for i in 1..<limit:
    if i mod 3 == 0 or i mod 5 == 0:
      total += i
  return total
```

### Nim Properties

- if an object property is the same name as a nim keyword, you must wrap it in backticks
```
  DeleteModelResponse* = ref object
    id*: string
    `object`*: string
    deleted*: bool
```

### Variables

Group `const`, `let`, and `var` declarations into blocks. Prefer `const` over `let`, and `let` over `var`. Pull magic values into named constants at the top of the file.

Constants use PascalCase. Variables use camelCase.

WRONG:
```nim
const MAX_RETRIES = 5
const GRAVITY = 9.81
let api_url = "https://example.com"
```

RIGHT:
```nim
const
  MaxRetries = 5
  Gravity = 9.81
let
  apiUrl = "https://example.com"
```

## Programming

- Don't use try/catch unless you have a very, very good reason to be handling the error at this level.
- never mask errors with catch: discard
- it's OK to allow errors to bubble up. we want things to be easy to debug and fail fast.
- returning in the middle of files is confusing, avoid doing it.
  - early returns at the start of the file is ok.
- try to make things as idempotent as possible. if a job runs every day, we should make sure it can be robust.
- never use booleans for 'success' or 'error'. If a function was successful, return nothing and do not throw an error. if a function failed, throw an error.

### Comments

- functions should have doc comments
- however code should otherwise not need comments. functions should be named properly and the code should be readable.
- comments may be ok for 'spooky at a distance' things in rare cases.
- comments should be complete sentences that are followed with a period.
