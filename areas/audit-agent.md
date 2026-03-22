# Audit Agent

Read-only audit agent that runs when the merge queue drains, checking spec and AGENTS.md compliance.

## Scope

- The audit agent runs when the merge queue fully drains (goes idle after processing one or more items). It does not block the merge queue or modify any code — it only produces a report.
- The audit checks two things:
  1. **Spec compliance**: Read `spec.md` and sample the codebase. Report divergences — features the spec describes that the code does not implement, code behaviors not reflected in the spec, contradictions between spec requirements and actual behavior.
  2. **AGENTS.md compliance**: Read `AGENTS.md` and the cumulative diff since the last audit. Report violations of project conventions.
- Trigger: the orchestrator tracks a "last audited commit" hash. When the merge queue drains, it compares the current default branch HEAD against the last audited commit. If they differ, it spawns the audit agent. If nothing merged, no audit runs.
- Secondary trigger: spec change. If the architect rewrites `spec.md`, an audit runs to catch "spec says X but code still does old-Y".
- The audit agent runs as a background agent using a shared pool slot (like managers and coders).
- The audit agent should be cheap: use a smaller/faster model (default Haiku), limit scope to the cumulative diff since the last audit plus `spec.md` and `AGENTS.md`.
- Output: markdown report written to `.scriptorium/logs/audit/` with a timestamp. Sections for spec drift and AGENTS.md violations, each item citing the relevant rule and the offending code location.
- Configuration: `agents.audit` in `scriptorium.json`, supporting `harness`, `model`, and `reasoningEffort`. Default model is `claude-haiku-4-5-20251001`.
- `scriptorium audit` CLI command runs the audit agent on demand.

## Spec References

- Section 19: Audit Agent.
