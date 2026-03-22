# 0118 — Add health directory to plan branch init layout

**Area:** health-cache

## Problem

The `health/` directory is listed as part of the authoritative plan branch layout
in the spec, but `PlanDirs` in `src/scriptorium/init.nim` (line 16) does not
include it. New workspaces created with `scriptorium init` won't have the
`health/` directory on the plan branch.

At runtime, `writeHealthCache` in `src/scriptorium/health_checks.nim` creates
the directory on-demand, so this is not a functional bug — but the plan branch
layout should be authoritative and match the spec.

## Task

1. Add `"health"` to the `PlanDirs` array in `src/scriptorium/init.nim` (line 16).
2. Update the init output message if it lists directories (line 152 area).
3. Add a unit test in `tests/test_scriptorium.nim` that verifies `PlanDirs`
   contains `"health"` (or verify via an init integration if one exists).

## Acceptance

- `scriptorium init` creates `health/.gitkeep` on the plan branch.
- Existing workspaces are unaffected (the directory is created on-demand at
  runtime by `writeHealthCache`).
