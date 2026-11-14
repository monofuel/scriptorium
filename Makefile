SHELL := bash
NIM ?= $(if $(wildcard .build/nim-2.2.14/bin/nim),$(CURDIR)/.build/nim-2.2.14/bin/nim,nim)
export NIM
export PATH := $(CURDIR)/.build/agent-tools/node_modules/.bin:$(if $(findstring /,$(NIM)),$(dir $(NIM)):$(PATH),$(PATH))
NIM_FLAGS ?= --hints:off --warnings:off
DOCKER_IMAGE ?= gitea.solution-nine.monofuel.dev/monolab/scriptorium:latest
DOCKER_PLATFORM ?= linux/amd64

.PHONY: setup agent-setup build test test-arc test-orc integration-test integration-test-codex integration-test-claude integration-test-grok integration-test-hermes e2e-test e2e-test-codex e2e-test-claude e2e-test-grok docker-build docker-build-push ci check-updates

setup: nim.cfg

nim.cfg: nimby.lock scripts/setup.nim
	$(NIM) r $(NIM_FLAGS) scripts/setup.nim

agent-setup: package.json package-lock.json
	$(NIM) r $(NIM_FLAGS) scripts/agent_setup.nim

build: nim.cfg
	$(NIM) c $(NIM_FLAGS) --nimcache:.build/nimcache/app -o:scriptorium src/scriptorium.nim

test: nim.cfg
	env -u CLAUDE_CODE_USE_BEDROCK $(NIM) r $(NIM_FLAGS) scripts/test_runner.nim unit

test-arc: nim.cfg
	env -u CLAUDE_CODE_USE_BEDROCK $(NIM) r $(NIM_FLAGS) --mm:arc --nimcache:.build/test-cache/acp-arc -o:.build/test-binaries/acp-arc tests/test_agent_runner.nim

test-orc: nim.cfg
	env -u CLAUDE_CODE_USE_BEDROCK $(NIM) r $(NIM_FLAGS) --mm:orc --nimcache:.build/test-cache/acp-orc -o:.build/test-binaries/acp-orc tests/test_agent_runner.nim

integration-test: nim.cfg
	$(NIM) r $(NIM_FLAGS) scripts/test_runner.nim integration
	$(MAKE) integration-test-codex integration-test-claude integration-test-grok

integration-test-codex: nim.cfg
	$(NIM) r $(NIM_FLAGS) scripts/test_runner.nim tests/integration_acp_harness.nim codex

integration-test-claude: nim.cfg
	$(NIM) r $(NIM_FLAGS) scripts/test_runner.nim tests/integration_acp_harness.nim claude

integration-test-grok: nim.cfg
	$(NIM) r $(NIM_FLAGS) scripts/test_runner.nim tests/integration_acp_harness.nim grok

integration-test-hermes: nim.cfg
	$(NIM) r $(NIM_FLAGS) scripts/test_runner.nim tests/integration_hermes_acp.nim

e2e-test: e2e-test-codex e2e-test-claude e2e-test-grok

e2e-test-codex: nim.cfg
	$(NIM) r $(NIM_FLAGS) scripts/test_runner.nim e2e codex

e2e-test-claude: nim.cfg
	$(NIM) r $(NIM_FLAGS) scripts/test_runner.nim e2e claude

e2e-test-grok: nim.cfg
	$(NIM) r $(NIM_FLAGS) scripts/test_runner.nim e2e grok

docker-build:
	docker buildx build --build-arg BUILD_COMMIT=$(shell git rev-parse --short HEAD) --platform $(DOCKER_PLATFORM) --load --tag $(DOCKER_IMAGE) .

docker-build-push:
	docker buildx build --build-arg BUILD_COMMIT=$(shell git rev-parse --short HEAD) --platform $(DOCKER_PLATFORM) --push --tag $(DOCKER_IMAGE) .

ci:
	act -W .github/workflows/build.yml

check-updates:
	npm outdated --prefix .build/agent-tools
