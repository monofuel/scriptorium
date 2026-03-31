# 0075 Update Makefile template with required make targets

**Area:** cli-init

## Description

Per V11 §39 and §35, the starter Makefile must include `test`, `integration-test`, `e2e-test`, and `build` targets that exit 0. The current template only has `test` and `build`.

**Current template** (`src/scriptorium/init.nim` line 12):
```makefile
.PHONY: test build

test:
	@echo "no tests configured"

build:
	@echo "no build configured"
```

**Required template:**
```makefile
.PHONY: test integration-test e2e-test build

test:
	@echo "no tests configured"

integration-test:
	@echo "no integration tests configured"

e2e-test:
	@echo "no e2e tests configured"

build:
	@echo "no build configured"
```

## Tasks

1. Update `MakefileTemplate` in `src/scriptorium/init.nim` to include `integration-test` and `e2e-test` targets.
2. Update the integration test in `tests/integration_cli.nim` ("init creates Makefile with placeholder targets when missing") to also check for `integration-test:` and `e2e-test:` in the generated content.
3. Run `make test` to confirm tests pass.

**Worktree:** /workspace/.scriptorium/worktrees/tickets/0082-0075-update-makefile-template-with-required-make-targets
