.PHONY: test integration-test integration-test-claude e2e-test e2e-test-claude build docker-build docker-build-push ci

DOCKER_IMAGE ?= gitea.solution-nine.monofuel.dev/monolab/scriptorium:latest
DOCKER_PLATFORM ?= linux/amd64

nim.cfg: nimby.lock
	nimby sync -g nimby.lock

build: nim.cfg scriptorium

scriptorium: src/scriptorium.nim
	nim c -o:scriptorium src/scriptorium.nim

test: nim.cfg
	@found=0; \
	for f in tests/test_*.nim; do \
		[ -e "$$f" ] || continue; \
		found=1; \
		echo "--- $$f ---"; \
		nim r "$$f" || exit 1; \
	done; \
	if [ $$found -eq 0 ]; then \
		echo "No unit tests found in tests/test_*.nim"; \
	fi

integration-test: nim.cfg
	@found=0; \
	for f in tests/integration_*.nim; do \
		[ -e "$$f" ] || continue; \
		found=1; \
		echo "--- $$f ---"; \
		nim r "$$f" || exit 1; \
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
		nim r "$$f" || exit 1; \
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

docker-build-push:
	docker buildx build \
		--platform $(DOCKER_PLATFORM) \
		--push \
		--tag $(DOCKER_IMAGE) \
		.
