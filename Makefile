# Local Antora build/serve via Podman (matches .github/workflows/gh-pages.yml)
#
#   make build   # generate ./www
#   make run     # serve ./www on http://localhost:8080
#   make clean   # remove build output

SHELL := /bin/bash

PORT ?= 8080
CONTAINER_NAME ?= ocp5-ea-showroom-www
NODE_IMAGE ?= docker.io/library/node:24-bookworm-slim
NGINX_IMAGE ?= docker.io/library/nginx:alpine

# SELinux volume labeling on Linux; omit on macOS (Podman machine)
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
  VOLUME_SUFFIX := :Z
else
  VOLUME_SUFFIX :=
endif

.PHONY: build run stop clean help

help:
	@echo "Targets:"
	@echo "  make build  - Build the Antora site into ./www (Podman)"
	@echo "  make run    - Serve ./www at http://localhost:$(PORT) (Podman/nginx)"
	@echo "  make stop   - Stop the local preview container"
	@echo "  make clean  - Remove ./www and .cache"

build:
	@command -v podman >/dev/null || { echo "podman is required"; exit 1; }
	podman run --rm \
	  --name ocp5-ea-showroom-antora \
	  -v "$(CURDIR):/work$(VOLUME_SUFFIX)" \
	  -w /work \
	  $(NODE_IMAGE) \
	  bash -c 'npm install --global @antora/cli@3.1 @antora/site-generator@3.1 @andrew-jones/antora-tabs-extension && antora generate site.yml --stacktrace'
	@echo "Build complete: $(CURDIR)/www"

run: stop
	@command -v podman >/dev/null || { echo "podman is required"; exit 1; }
	@test -d www || $(MAKE) build
	podman run --rm -d \
	  --name $(CONTAINER_NAME) \
	  -p $(PORT):80 \
	  -v "$(CURDIR)/www:/usr/share/nginx/html:ro$(VOLUME_SUFFIX)" \
	  $(NGINX_IMAGE) >/dev/null
	@echo "Serving ./www at http://localhost:$(PORT)"
	@echo "Stop with: make stop"

stop:
	-@podman rm -f $(CONTAINER_NAME) >/dev/null 2>&1 || true

clean: stop
	rm -rf www .cache
