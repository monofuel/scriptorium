# E2E Euler Test Plan

This document describes a proposed end-to-end integration test based on Project Euler problem #1.

## Goal

Add at least one real end-to-end test that validates the full Scriptorium flow with a small, deterministic coding task.

The target task is:

> If we list all the natural numbers below 10 that are multiples of 3 or 5, we get 3, 5, 6 and 9. The sum of these multiples is 23. Find the sum of all multiples of 3 or 5 below 1000.

The coding agent should create a Nim program named `multiples.nim` that prints only the answer number:

```text
233168
```

## Why This Test

This task is a good E2E candidate because it is:

- Small.
- Deterministic.
- Easy to verify.
- Cheap to run compared to larger live tasks.

It gives us a concrete way to confirm that the full live flow still works without manual testing every time.

## Intended E2E Scope

This test should validate as much of the real flow as possible:

1. Initialize a fresh temporary repository.
2. Seed a real `spec.md` describing the Euler task.
3. Run the real orchestrator with real model execution.
4. Let the Architect produce areas.
5. Let the Manager produce tickets.
6. Let the Coding agent implement `multiples.nim`.
7. Require the Coding agent to call `submit_pr`.
8. Let the merge queue process the result.
9. Verify the final result landed on `master`.
10. Verify the repository quality gates pass.

This is intentionally broader than the current live tests that begin from a pre-seeded ticket.

## Fixture Repository Strategy

The fixture repository should be generated at runtime, not checked into the repository as a static fixture.

Recommended approach:

- Put reusable fixture-building helpers under `tests/support/`.
- Create disposable integration repositories under `/tmp/scriptorium/integration/`.

Recommended generated path pattern:

```text
/tmp/scriptorium/integration/<case-name>_<random-or-unique-suffix>
```

This is preferred over a committed fixture repo because:

- The setup is small.
- Fresh git history is useful for each run.
- The tests should be isolated and disposable.
- Failures are easier to inspect in `/tmp`.
- The approach will scale better if more E2E cases are added later.

## Suggested Fixture Helper Responsibilities

A shared helper module should eventually handle:

- Creating a temporary repository.
- Running `git init`.
- Configuring git user identity.
- Running `scriptorium --init`.
- Writing a minimal `Makefile`.
- Writing `scriptorium.json`.
- Seeding `spec.md`.
- Starting or locating the CLI binary.
- Waiting for plan and ticket state transitions.
- Inspecting final repository state on `master`.

This should reduce duplicated setup logic across future live E2E tests.

## Proposed Euler Fixture Repo

The generated repository should contain a minimal `Makefile` with both required quality gates:

- `make test`
- `make integration-test`

Both targets should validate the real repository artifact rather than agent stdout.

Recommended validation:

- Confirm `multiples.nim` exists.
- Run the Nim program.
- Assert the output is exactly `233168`.
- Allow only the answer number and trailing newline.

This keeps the assertions focused on durable repository behavior.

## Recommended Spec Content

The seeded spec should be explicit and narrow. It should tell the system to:

- Create a Nim program named `multiples.nim`.
- Solve the Project Euler #1 problem.
- Print only the numeric answer.
- Avoid extra output.
- Use Nim.
- Call `submit_pr` when complete.

The clearer the requirement, the better the odds of stable live execution.

## Main Assertions

The E2E test should primarily assert on repository state and execution results, not on log text.

Recommended assertions:

- `areas/` was created from the spec.
- At least one ticket was created.
- A ticket moved through `open`, `in-progress`, and `done`.
- The merge queue was populated and later emptied.
- `master` contains `multiples.nim`.
- `make test` passes on `master`.
- `make integration-test` passes on `master`.
- Running `multiples.nim` prints exactly `233168`.

## Stability Notes

This test will still be somewhat brittle because it uses real model behavior. To reduce brittleness:

- Keep the task narrow and deterministic.
- Assert on final artifacts and command success.
- Avoid stdout scanning as the primary correctness signal.
- Prefer git state, file state, and command exit codes.

## Future Extension

If this pattern works well, similar live E2E tests could be added for:

- Another small deterministic coding problem.
- A negative case where `submit_pr` is missing.
- A quality-gate failure case where generated code is wrong.
- A full-flow test with different task wording to probe planning robustness.

## Current Recommendation

Start with one high-signal live E2E test for the Euler problem.

If it proves useful and not too flaky, build one or two more tests on the same fixture helper infrastructure rather than adding many live E2E cases at once.
