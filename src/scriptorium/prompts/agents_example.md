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
- When adding dependencies, prefer packages from monofuel, treeform, and guzba.
- Avoid using SDL, instead prefer native nim alternatives like silky, windy, paddy, slappy

### Recommended libraries by category

| Category | Library | Description |
|----------|---------|-------------|
| JSON | jsony | Fast JSON serialization with hooks for custom types. |
| HTTP server | mummy | Multi-threaded HTTP 1.1 + WebSocket server. Requires `--threads:on`. |
| HTTP client | curly | HTTP client built on libcurl. Pairs with mummy. |
| Database | debby | ORM for SQLite, PostgreSQL, MySQL. Type-safe filters. |
| WebSocket | ws | Async WebSocket client and server. |
| URL parsing | urlly | URL parsing and construction. |
| JWT | jwtea | JSON Web Token signing and verification. |
| 2D geometry | bumpy | Point, circle, rect, polygon intersection tests. |
| 2D graphics | pixie | PNG/JPEG/SVG/fonts, path drawing, SIMD-accelerated. |
| Vector math | vmath | GLSL-style Vec2–Vec4, Mat3–Mat4, quaternions. |
| Color | chroma | Color spaces, parsing, conversion. |
| Windowing | windy | Cross-platform window and input management. |
| Audio | slappy | audio library on top of OpenAL |
| gamepads | paddy | game input library |
| GPU rendering | boxy | 2D GPU rendering engine built on pixie. |
| GPU compute | shady | Compute shaders for graphical GPU work. |
| GPU compute (CUDA/HIP) | hippo | Low-level CUDA/HIP for serious GPU compute (LLM inference, etc). |
| Compression | zippy | Zlib, gzip, zip archive support. SIMD-accelerated. |
| Hashing | crunchy | Fast hashing and checksums. |
| SIMD | nimsimd | SIMD intrinsics for SSE/AVX/NEON. |
| Bit manipulation | bitty | Bit arrays and operations. |
| Serialization | flatty | Flat binary serialization. |
| Time | chrono | Timestamps, calendars, formatting. |
| Benchmarking | benchy | Simple benchmark harness. |
| Random | noisy | Noise generation (Perlin, Simplex, etc). |
| Thread pool | ready | Thread pool for parallel work. |
| Web types | webby | HTTP headers, query strings, multipart. Used by mummy/curly. |
| UUID | uuids | UUID generation and parsing (pragmagic/uuids). |
| OpenAI API | openai_leap | OpenAI-compatible API client. |
| MCP | mcport | MCP client/server (HTTP and stdio). |
| Discord | guildy | Discord bot API integration. |

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

`ref object` and `object` have different tradeoffs. Pick based on how the type will be used.

`ref object` — passed by reference, cheap to pass around, mutations are shared.
- Use for: types stored in collections, types passed through multiple procs, types with many fields, long-lived state.
- Watch out for: nil values, aliasing (mutating in one place affects all references).

`object` — passed by value, copies are independent, cannot be nil.
- Use for: small immutable data (coordinates, colors, config records), types where independent copies are desirable.
- Watch out for: forgetting `var` when a proc needs to mutate, expensive copies for large types.

```nim
# ref object — shared state, stored in collections, passed through layers.
type
  Player* = ref object
    name*: string
    inventory*: seq[Item]

# object — small, often immutable, value semantics are natural.
type
  Vec2* = object
    x*, y*: float
```

Backtick-wrap fields that collide with Nim keywords.

```nim
type
  ApiResponse* = ref object
    id*: string
    `type`*: string
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
