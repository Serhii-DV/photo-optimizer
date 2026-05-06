# ==========================================================
# Photo Optimizer Makefile
# ==========================================================

# Default target
.DEFAULT_GOAL := help

.PHONY: help
help: ## Display this help message
	@printf "\033[33mUsage:\033[0m\n  make [target] [arg=\"val\"...]\n\n\033[33mTargets:\033[0m\n"
	@grep -hE '^[a-zA-Z0-9_-]+:.*## .*$$' $(MAKEFILE_LIST) | sort | \
	  awk 'BEGIN {FS = ": ## "}; {printf "  \033[32m%-15s\033[0m %s\n", $$1, $$2}'

.PHONY: install
install: ## Install dependencies
	sudo apt-get update
	sudo apt-get install webp ffmpeg exiv2 libimage-exiftool-perl
