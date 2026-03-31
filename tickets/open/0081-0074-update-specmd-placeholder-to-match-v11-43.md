# 0074 Update spec.md placeholder to match V11 §43

**Area:** cli-init

## Description

The `SpecPlaceholder` constant in `src/scriptorium/init.nim` needs updating to match the V11 §43 spec.

**Current:**
```
# Spec

Run `scriptorium plan` to build your spec with the Architect.
```

**Required:**
```
# Spec

This is a new project. See AGENTS.md for project conventions.

Run `scriptorium plan` to build your spec with the Architect.
```

## Tasks

1. Update the `SpecPlaceholder` constant in `src/scriptorium/init.nim` (line 8) to include the new line.
2. Update the `SpecPlaceholder` constant in `tests/test_init.nim` (line 6) to match.
3. Update `tests/integration_cli.nim` test "init spec.md references AGENTS.md" — it already checks for `AGENTS.md` in spec content, so it should still pass, but verify.
4. Run `make test` to confirm all init tests pass.
