# Project Instructions

This repository uses Nim and keeps dependencies minimal.

## General

- Prefer clear, small changes.
- Keep implementations minimal and easy to debug.
- Prefer simple dependencies.
- When adding Nim dependencies, prefer packages from monofuel, treeform, and guzba when they fit the task.
- Let errors bubble up naturally unless there is a strong reason to handle them locally.
- Do not hide failures with empty catch blocks or discarded errors.
- Prefer deterministic behavior and idempotent operations.
- Do not reference, clean, or manage `.nimcache` directories. The build system handles them.

## Dependencies

- MUST use nimby (not nimble) for dependency management.
- Recommended libraries by category:
  - JSON: jsony
  - HTTP server: mummy
  - Database: debby
  - WebSocket: ws
  - Collision/geometry: bumpy
  - Image: pixie
  - Vector math: vmath

## Variables

Group `const`, `let`, and `var` declarations into blocks. Prefer `const` over `let`, and `let` over `var`. Pull magic values into named constants at the top of the file.

Constants use PascalCase. Variables use camelCase.

WRONG:
```nim
const MAX_RETRIES = 5
const GRAVITY = 9.81
let api_url = "https://example.com"
var retry_count = 0
```

RIGHT:
```nim
const
  MaxRetries = 5
  Gravity = 9.81
let
  apiUrl = "https://example.com"
var
  retryCount = 0
```

- Prefer `&` string interpolation over `fmt`.
- Do not call functions directly inside interpolated strings when a named variable would be clearer.

## Imports

One `import` block. Use bracket syntax. Order: std/ then libraries then local. No quotes on paths.

WRONG:
```nim
import std/os
import std/strutils
import jsony
import ./models
import ./logs
```

RIGHT:
```nim
import
  std/[os, strutils],
  jsony,
  ./[models, logs]
```

## Procedures

Doc comments go INSIDE the proc, not above it. Use `##`. All comments are complete sentences: capital first letter, period at end.

WRONG:
```nim
# Calculate the sum of multiples.
proc sumOfMultiples(limit: int): int =
  var total = 0
  for i in 1..<limit:
    if i mod 3 == 0 or i mod 5 == 0:
      total += i
  return total
```

RIGHT:
```nim
proc sumOfMultiples(limit: int): int =
  ## Calculate the sum of all multiples of 3 or 5 below the limit.
  var total = 0
  for i in 1..<limit:
    if i mod 3 == 0 or i mod 5 == 0:
      total += i
  return total
```

## Object Types

- Prefer `ref object` for types that will be passed around.
- Backtick-wrap fields that collide with Nim keywords.

```nim
type
  DeleteModelResponse* = ref object
    id*: string
    `object`*: string
    deleted*: bool
```

## Error Handling

- Do not add `try/except` unless handling the error at that layer is genuinely necessary.
- Do not use `except: discard`.
- Failing loudly is preferred over masking problems.

## Testing

- Keep tests focused on observable behavior.
- Prefer assertions on files, return values, and command success over loose stdout scanning.
- If a task changes runtime behavior, update or add tests to cover it.
- Add a `tests/config.nims` file with `--path:"../src"` so tests can import project modules without ugly relative paths.

## Coding Tasks

- Keep the implementation minimal.
- Avoid unrelated refactors.
- When a task asks for a command-line program, make the output exact and avoid extra text.
