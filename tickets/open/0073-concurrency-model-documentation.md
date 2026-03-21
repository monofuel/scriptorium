# Concurrency Model Documentation

**Area:** parallel-execution

**Depends:** 0071

## Problem

V13 §33 requires documenting the concurrency model to clarify which agents are sequential vs parallel, how the shared slot pool works, and how merge conflicts are handled.

## Requirements

Add a `## Concurrency Model` section to the project's `AGENTS.md` (or a dedicated doc file if more appropriate) covering:

1. **Strictly sequential agents**: Architect (reads spec, writes areas, runs at most once per tick, protected by plan lock, must complete before managers) and Review/Merge (one merge queue item at a time, sequential to guarantee default branch health).
2. **Parallel agents (shared slot pool)**: Manager (one area per invocation, multiple can run in parallel) and Coding agent (one ticket per invocation, multiple can run in parallel in independent areas). Both share the `maxAgents` slot pool.
3. **Interleaved execution**: Managers and coders interleaved across ticks — orchestrator does not wait for all managers to finish before starting coders.
4. **Merge conflict handling**: Parallel coding agents may produce merge conflicts on shared files. Sequential merge process catches conflicts by merging default branch into ticket branch before testing. Conflicting tickets sent back for another coding attempt with conflict context. Area-based separation makes conflicts less likely but system handles them gracefully.
5. **Slot arithmetic**: Example — if `maxAgents` is 4 and 2 managers are running, only 2 slots remain for coders (and vice versa).

Keep the documentation concise. `make test` must still pass.
