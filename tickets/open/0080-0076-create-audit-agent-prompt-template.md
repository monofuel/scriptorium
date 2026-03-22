<!-- file: tickets/open/0076-audit-prompt-template.md -->
# 0076 — Create audit agent prompt template

**Area:** audit-agent

Create the prompt template for the audit agent and wire it into the prompt catalog.

## Details

1. Create `src/scriptorium/prompts/audit_agent.md` with a prompt template that instructs the agent to:
   - Read `spec.md` and sample the codebase to find spec divergences (features spec describes but code doesn't implement, code behaviors not in spec, contradictions).
   - Read `AGENTS.md` and review the cumulative diff to find convention violations.
   - Output a structured markdown report with two sections: "Spec Drift" and "AGENTS.md Violations".
   - Each finding should cite the relevant rule/spec section and the offending code location.
   - Use placeholders: `{{SPEC_CONTENT}}`, `{{AGENTS_MD_CONTENT}}`, `{{CUMULATIVE_DIFF}}`, `{{REPO_PATH}}`.

2. In `src/scriptorium/prompt_catalog.nim`, add:
   ```nim
   const AuditAgentTemplate* = staticRead(PromptDirectory & "audit_agent.md")
