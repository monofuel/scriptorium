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

## Nim

- Use Nim for source code and tests unless the task clearly requires something else.
- Prefer `const` over `let`, and `let` over `var`.
- Group `const`, `let`, and `var` declarations together.
- Avoid magic values in code. Pull important values up into named constants.
- Prefer `&` string interpolation over `fmt`.
- Do not call functions directly inside interpolated strings when a named variable would be clearer.

## Imports

- Put standard library imports first, then third-party libraries, then local imports.
- Group imports with bracket syntax when it improves readability.

## Procedures

- Every proc should have a Nim doc comment.
- Nim doc comments should use `##` and be complete sentences with punctuation.
- Prefer readable names over extra comments.

## Error Handling

- Do not add `try/except` unless handling the error at that layer is genuinely necessary.
- Do not use `except: discard`.
- Failing loudly is preferred over masking problems.

## Testing

- Keep tests focused on observable behavior.
- Prefer assertions on files, return values, and command success over loose stdout scanning.
- If a task changes runtime behavior, update or add tests to cover it.

## Coding Tasks

- Keep the implementation minimal.
- Avoid unrelated refactors.
- When a task asks for a command-line program, make the output exact and avoid extra text.
