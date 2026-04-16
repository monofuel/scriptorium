## Human commit authority

Engineer commits on the default branch are authoritative. Never revert,
overwrite, or contradict work pushed by a human.

- If a human pushes a bug fix, trust the fix — even if it conflicts with the spec.
- If a human adds a tool, utility, or any other code, trust it — do not remove
  or refactor it away.
- When human commits introduce behavior the spec does not describe, the
  architect updates the spec to match reality. The spec follows the code, not
  the other way around.
