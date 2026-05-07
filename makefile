# ==========================================================
# Photo Optimizer Makefile
# ==========================================================

# Default target
.DEFAULT_GOAL := help

ALIAS_NAME ?= optimize-media
ALIAS_FILE ?= $(HOME)/.bash_aliases
OPTIMIZE_SCRIPT := $(abspath optimize.sh)

.PHONY: help
help: ## Display this help message
	@printf "\033[33mUsage:\033[0m\n  make [target] [arg=\"val\"...]\n\n\033[33mTargets:\033[0m\n"
	@grep -hE '^[a-zA-Z0-9_-]+:.*## .*$$' $(MAKEFILE_LIST) | sort | \
	  awk 'BEGIN {FS = ": ## "}; {printf "  \033[32m%-15s\033[0m %s\n", $$1, $$2}'

.PHONY: install
install: ## Install dependencies
	sudo apt-get update
	sudo apt-get install webp ffmpeg libimage-exiftool-perl
	chmod +x optimize.sh
	chmod +x verify_exif.sh

.PHONY: install-alias
install-alias: ## Add or update a shell alias for optimize.sh
	@mkdir -p "$(dir $(ALIAS_FILE))"
	@touch "$(ALIAS_FILE)"
	@if grep -Eq '^alias $(ALIAS_NAME)=' "$(ALIAS_FILE)"; then \
		sed -i "s|^alias $(ALIAS_NAME)=.*|alias $(ALIAS_NAME)='$(OPTIMIZE_SCRIPT)'|" "$(ALIAS_FILE)"; \
	else \
		printf "\n# photo-optimizer\nalias $(ALIAS_NAME)='$(OPTIMIZE_SCRIPT)'\n" >> "$(ALIAS_FILE)"; \
	fi
	@printf "Alias installed: %s='%s'\n" "$(ALIAS_NAME)" "$(OPTIMIZE_SCRIPT)"
	@printf "Reload your shell or run: source %s\n" "$(ALIAS_FILE)"
