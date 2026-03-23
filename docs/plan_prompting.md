# Prompting the architect

The architect reads and writes the **spec**, not the code. When crafting
prompts for `plan.sh`, think in terms of what the system *should do*, not how
the current implementation works.

## Principles

1. **Spec-focused, not implementation-focused.** The architect doesn't know
   about function names, file paths, or string matching logic. Talk about
   behaviors and rules, not code.

2. **Reference spec sections.** The spec is organized by topic (e.g. §3
   Orchestrator Run Loop, §12 Resource Management). Point the architect at
   the relevant sections so it knows where to make changes.

3. **Describe the desired behavior, not the fix.** Instead of "remove the 429
   substring check in shared_state.nim", say "remove rate limit detection —
   the coding harness handles retries internally."

4. **Keep it short.** The architect is capable of filling in details. Give it
   the *what* and *why*, not a step-by-step implementation plan. A few
   sentences is usually enough.

5. **Let the architect decide the plan.** The architect will break the spec
   changes into areas and tickets. Don't prescribe ticket structure or
   implementation order in the prompt.

## Examples

Bad (implementation-focused):
> Remove the isRateLimited() function in shared_state.nim that does substring
> matching on "429". Change the orchestrator tick loop to not call
> isRateLimitBackoffActive(). Delete the RateLimitBaseBackoffSeconds constant.

Good (spec-focused):
> In §12 (Resource Management), remove the rate limit detection and
> backpressure system entirely. The coding harness handles HTTP 429 retries
> internally. In §3 (Orchestrator Run Loop), replace the rate limit check
> with a staggered start rule: start at most 1 new coding agent per tick to
> avoid burst-spawning.

Bad (too prescriptive):
> Create 5 tickets: one for removing shared_state rate limit code, one for
> updating orchestrator.nim tick loop, one for removing the backoff constants,
> one for adding a lastAgentStartTime variable, one for tests.

Good (letting the architect decide):
> Remove rate limit detection from the spec. Replace it with staggered agent
> starts — at most 1 new coding agent per tick. Update the relevant sections.
