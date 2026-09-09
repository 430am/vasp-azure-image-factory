# VASP HPC image factory.
#
# Configuration comes from the environment - no subscription data is stored in this
# repository. Export the PKR_VAR_* values listed in the README before building.
SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

PACKER_DIR  := packer
SCRIPTS_DIR := scripts
INFRA_DIR   := infra

GIT_SHA       ?= $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
IMAGE_VERSION ?=

SHELL_SCRIPTS := $(shell find $(SCRIPTS_DIR) -name '*.sh')
VARIANTS      := hbv3 hbv4 nca100 ndh100

# Placeholder values so that `packer validate` runs without credentials or Azure access.
VALIDATE_VARS := \
	-var subscription_id=00000000-0000-0000-0000-000000000000 \
	-var tenant_id=00000000-0000-0000-0000-000000000000 \
	-var location=placeholder \
	-var resource_group=placeholder-gallery-rg \
	-var gallery_name=placeholdergallery \
	-var image_version=0.0.0

# Retain the temporary build VM after a failure for troubleshooting. Never set in CI.
KEEP_FAILED_BUILD_VM ?= 0
ON_ERROR := $(if $(filter 1,$(KEEP_FAILED_BUILD_VM)),-on-error=abort,-on-error=cleanup)

# Region and SKU are pinned per variant in packer/<variant>.pkrvars.hcl, not here.
BUILD_ENV_VARS := PKR_VAR_subscription_id PKR_VAR_tenant_id \
	PKR_VAR_resource_group PKR_VAR_gallery_name

define require_env
	@for v in $(1); do \
		if [[ -z "$${!v:-}" ]]; then echo "error: $$v is not set (see README)" >&2; exit 1; fi; \
	done
endef

define require_version
	@if [[ -z "$(IMAGE_VERSION)" ]]; then \
		echo "error: IMAGE_VERSION is not set, e.g. make $@ IMAGE_VERSION=1.0.0" >&2; exit 1; fi
	@if ! [[ "$(IMAGE_VERSION)" =~ ^[0-9]+\.[0-9]+\.[0-9]+$$ ]]; then \
		echo "error: IMAGE_VERSION must be major.minor.patch" >&2; exit 1; fi
endef

.PHONY: help init validate fmt lint packer-validate infra-validate \
	build-hbv3 build-hbv4 build-a100 build-h100 \
	test-hbv3 test-hbv4 test-a100 test-h100 clean

help: ## Show available targets
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk -F':.*?## ' '{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

init: ## Install Packer plugins and check required tooling
	@command -v packer >/dev/null || { echo "error: packer is not installed" >&2; exit 1; }
	@command -v az >/dev/null || { echo "error: azure-cli is not installed" >&2; exit 1; }
	packer init $(PACKER_DIR)
	@az bicep install >/dev/null 2>&1 || az bicep upgrade >/dev/null 2>&1 || true
	@echo "init complete"

validate: fmt lint packer-validate infra-validate ## Run every offline validation (no Azure resources created)

fmt: ## Check Packer formatting
	packer fmt -check -diff $(PACKER_DIR)

lint: ## Check shell script syntax (and shellcheck when available)
	@for s in $(SHELL_SCRIPTS); do bash -n "$$s" || exit 1; done
	@echo "bash -n: OK ($(words $(SHELL_SCRIPTS)) scripts)"
	@if command -v shellcheck >/dev/null; then \
		shellcheck -x $(SHELL_SCRIPTS); echo "shellcheck: OK"; \
	else \
		echo "shellcheck not installed - skipped"; \
	fi

packer-validate: ## Validate every Packer image configuration
	packer init $(PACKER_DIR)
	@for v in $(VARIANTS); do \
		echo "validating $$v"; \
		packer validate $(VALIDATE_VARS) -var-file=$(PACKER_DIR)/$$v.pkrvars.hcl $(PACKER_DIR) || exit 1; \
	done

infra-validate: ## Compile the Bicep infrastructure
	@command -v az >/dev/null || { echo "error: azure-cli is not installed" >&2; exit 1; }
	az bicep build --file $(INFRA_DIR)/main.bicep --stdout >/dev/null
	az bicep build-params --file $(INFRA_DIR)/main.bicepparam --stdout >/dev/null
	@echo "bicep: OK"

# $(1) = pkrvars basename
define packer_build
	$(call require_env,$(BUILD_ENV_VARS))
	$(require_version)
	packer build $(ON_ERROR) \
		-var git_sha=$(GIT_SHA) \
		-var image_version=$(IMAGE_VERSION) \
		-var-file=$(PACKER_DIR)/$(1).pkrvars.hcl \
		$(PACKER_DIR)
endef

# $(1) = pkrvars basename. Region, SKU, image definition and build type are read from
# that file so it stays the single source of truth for the variant.
define image_test
	$(call require_env,$(BUILD_ENV_VARS))
	$(require_version)
	@f=$(PACKER_DIR)/$(1).pkrvars.hcl; \
	get() { awk -F'"' -v k="$$1" '$$0 ~ "^[[:space:]]*"k"[[:space:]]*=" {print $$2; exit}' "$$f"; }; \
	region="$$(get location)"; region="$${region:-$${PKR_VAR_location:-}}"; \
	if [[ -z "$$region" ]]; then \
		echo "error: no region for $(1). Set location in $$f, or export PKR_VAR_location." >&2; exit 1; fi; \
	SUBSCRIPTION_ID="$$PKR_VAR_subscription_id" \
	LOCATION="$$region" \
	GALLERY_RESOURCE_GROUP="$$PKR_VAR_resource_group" \
	GALLERY_NAME="$$PKR_VAR_gallery_name" \
	IMAGE_DEFINITION="$$(get image_definition)" \
	TEST_VM_SIZE="$$(get target_vm_size)" \
	IMAGE_VERSION="$(IMAGE_VERSION)" \
		$(SCRIPTS_DIR)/test/image-smoke-test.sh "$$(get build_type)"
endef

build-hbv3: ## Build and publish the HBv3 CPU image (znver3, billable)
	$(call packer_build,hbv3)

build-hbv4: ## Build and publish the HBv4 CPU image (znver4, billable)
	$(call packer_build,hbv4)

build-a100: ## Build and publish the NC_A100_v4 GPU image (cc80, billable)
	$(call packer_build,nca100)

build-h100: ## Build and publish the ND_H100_v5 GPU image (cc90, billable)
	$(call packer_build,ndh100)

test-hbv3: ## Deploy an HBv3 VM from the gallery image, validate it, then destroy it
	$(call image_test,hbv3)

test-hbv4: ## Deploy an HBv4 VM from the gallery image, validate it, then destroy it
	$(call image_test,hbv4)

test-a100: ## Deploy an NC_A100_v4 VM from the gallery image, validate it, then destroy it
	$(call image_test,nca100)

test-h100: ## Deploy an ND_H100_v5 VM from the gallery image, validate it, then destroy it
	$(call image_test,ndh100)

clean: ## Remove local build output
	rm -f manifest.json
	rm -rf $(PACKER_DIR)/.packer.d packer_cache
