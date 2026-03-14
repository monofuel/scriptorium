.PHONY: test integration-test integration-test-claude e2e-test e2e-test-claude build docker-build docker-build-push ci check-updates

DOCKER_IMAGE ?= gitea.solution-nine.monofuel.dev/monolab/scriptorium:latest
DOCKER_PLATFORM ?= linux/amd64

nim.cfg: nimby.lock
	nimby sync -g nimby.lock

build: nim.cfg scriptorium

BUILD_COMMIT ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)

scriptorium: src/scriptorium.nim
	nim c -d:BuildCommitHash=$(BUILD_COMMIT) -o:scriptorium src/scriptorium.nim

NIM_TEST_FLAGS ?= --hints:off --warnings:off

test: nim.cfg
	@files=$$(ls tests/test_*.nim 2>/dev/null); \
	if [ -z "$$files" ]; then \
		echo "No unit tests found in tests/test_*.nim"; \
		exit 0; \
	fi; \
	fail=0; \
	pids=""; \
	for f in $$files; do \
		( nim r $(NIM_TEST_FLAGS) "$$f" 2>&1 | sed "s|^|[$$f] |" ) & \
		pids="$$pids $$!"; \
	done; \
	for pid in $$pids; do \
		wait $$pid || fail=1; \
	done; \
	exit $$fail

integration-test: nim.cfg
	@found=0; \
	for f in tests/integration_*.nim; do \
		[ -e "$$f" ] || continue; \
		found=1; \
		echo "--- $$f ---"; \
		nim r $(NIM_TEST_FLAGS) "$$f" || exit 1; \
	done; \
	if [ $$found -eq 0 ]; then \
		echo "No integration tests found in tests/integration_*.nim"; \
	fi

integration-test-claude:
	SCRIPTORIUM_TEST_MODEL=claude-sonnet-4-6 \
	SCRIPTORIUM_TEST_HARNESS=claude-code \
	$(MAKE) integration-test

e2e-test: nim.cfg
	@found=0; \
	for f in tests/e2e_*.nim; do \
		[ -e "$$f" ] || continue; \
		found=1; \
		echo "--- $$f ---"; \
		nim r $(NIM_TEST_FLAGS) "$$f" || exit 1; \
	done; \
	if [ $$found -eq 0 ]; then \
		echo "No e2e tests found in tests/e2e_*.nim"; \
	fi

e2e-test-claude:
	SCRIPTORIUM_TEST_MODEL=claude-sonnet-4-6 \
	SCRIPTORIUM_TEST_HARNESS=claude-code \
	$(MAKE) e2e-test

ci:
	act -W .github/workflows/build.yml

docker-build:
	docker buildx build \
		--platform $(DOCKER_PLATFORM) \
		--load \
		--tag $(DOCKER_IMAGE) \
		.

check-updates:
	@echo "Checking for npm package updates..."
	@echo "--- @openai/codex ---"
	@pinned=$$(grep 'CODEX_VERSION=' Dockerfile | head -1 | sed 's/.*=//'); \
	latest=$$(npm view @openai/codex version 2>/dev/null); \
	echo "  Pinned: $$pinned"; \
	echo "  Latest: $$latest"; \
	if [ "$$pinned" != "$$latest" ]; then echo "  ** Update available **"; fi
	@echo "--- @anthropic-ai/claude-code ---"
	@pinned=$$(grep 'CLAUDE_CODE_VERSION=' Dockerfile | head -1 | sed 's/.*=//'); \
	latest=$$(npm view @anthropic-ai/claude-code version 2>/dev/null); \
	echo "  Pinned: $$pinned"; \
	echo "  Latest: $$latest"; \
	if [ "$$pinned" != "$$latest" ]; then echo "  ** Update available **"; fi

docker-build-push:
	docker buildx build \
		--platform $(DOCKER_PLATFORM) \
		--push \
		--tag $(DOCKER_IMAGE) \
		.
