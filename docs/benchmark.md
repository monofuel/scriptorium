# Benchmark Plan

This document defines the initial benchmarking rollout for scriptorium using `benchy`
(reference: `../benchy`).

## Scope

- [ ] Benchmark deterministic local code paths only (no real network/codex API calls).
- [ ] Run benchmarks in release mode only.
- [ ] Keep benchmark execution separate from `make test` and `make integration-test`.

## Stage 1: Benchmark Scaffolding

- [ ] Add `benchy` as a development dependency for benchmark files.
- [ ] Create `tests/bench_orchestrator.nim`.
- [ ] Create `tests/bench_harness_codex.nim`.
- [ ] Add `make bench` target to run `tests/bench_*.nim` with `-d:release`.
- [ ] Ensure benchmark files compile and run locally with one command.

## Stage 2: Orchestrator Benchmarks

- [ ] Add fixture builder helpers for synthetic plan states (10, 100, 1000 tickets).
- [ ] Benchmark `assignOldestOpenTicket` across fixture sizes.
- [ ] Benchmark `processMergeQueue` for queue sizes (1, 10, 100) using local fixtures.
- [ ] Benchmark one bounded `runOrchestratorForTicks` pass using fake agent runners.
- [ ] Record minimum/average/stddev output from `benchy` for each scenario.

## Stage 3: Codex Harness Benchmarks (Stubbed)

- [ ] Benchmark `buildCodexExecArgs` as a micro-benchmark.
- [ ] Benchmark `runCodex` success path using a local fake codex script.
- [ ] Benchmark `runCodex` retry path (first fail, second success) using local fake scripts.
- [ ] Benchmark timeout handling path with a local fake stalled script.
- [ ] Ensure all codex benchmark scenarios avoid real API usage.

## Stage 4: Reproducibility

- [ ] Add shared benchmark metadata output (git SHA, Nim version, date/time).
- [ ] Add warm-up setup before measured benchmark loops.
- [ ] Fix random seeds where randomness exists.
- [ ] Ensure benchmark temp paths are isolated per run.

## Stage 5: Baseline And Tracking

- [ ] Create `docs/benchmarks/baseline.md` with initial benchmark results.
- [ ] Store command lines used to collect baseline results.
- [ ] Define manual regression threshold (for example: investigate if >20% slower).
- [ ] Add a short “how to compare current vs baseline” section.

## Stage 6: Optional CI Follow-Up

- [ ] Add a dedicated benchmark workflow (`workflow_dispatch` only).
- [ ] Run `make bench` in that workflow and upload benchmark logs as artifacts.
- [ ] Keep benchmarks out of default push/PR CI until results stabilize.

