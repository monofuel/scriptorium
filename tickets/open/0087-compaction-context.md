**ID:** 0074
**Title:** Forward continuationPromptBuilder to ClaudeCodeRunRequest in agent_runner
**Area:** compaction-context
**Description:**

In `src/scriptorium/agent_runner.nim`, the `runAgent` proc forwards `continuationPromptBuilder` to the codex and typoi harnesses but **not** to the Claude Code harness. At line 171, only `continuationPrompt` is set — `continuationPromptBuilder` is missing from the `ClaudeCodeRunRequest` construction (lines 156–176).

Add `continuationPromptBuilder: request.continuationPromptBuilder` to the `ClaudeCodeRunRequest` object literal in the `harnessClaudeCode` branch, matching how it is already done for codex (line 137) and typoi (line 205).

**Verify:** `make test` passes. Grep for `continuationPromptBuilder` and confirm all three harness branches in `runAgent` forward it.
````

````markdown
**ID:** 0075
**Title:** Implement AGENTS.md re-injection in continuation prompt builder for coding agent
**Area:** compaction-context
**Description:**

When a coding agent retries after a timeout or stall, the continuation prompt should re-inject critical project rules from AGENTS.md so the agent doesn't drift after context compaction.

In `src/scriptorium/prompt_builders.nim`, add a new proc:

```nim
proc buildAgentsRulesContinuation*(workingDir: string): string
