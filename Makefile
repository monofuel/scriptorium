.PHONY: test integration-test build docker-build docker-build-push ci

DOCKER_IMAGE ?= gitea.solution-nine.monofuel.dev/monolab/scriptorium:latest
DOCKER_PLATFORM ?= linux/amd64

build: scriptorium

scriptorium: src/scriptorium.nim
	nim c -o:scriptorium src/scriptorium.nim

test:
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

integration-test:
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
