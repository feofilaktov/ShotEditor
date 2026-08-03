.DEFAULT_GOAL := help
.PHONY: help build run test release dmg cert clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Debug build
	swift build

run: ## Build and launch the app
	./run.sh

test: ## Run unit tests + visual smoke test
	./scripts/run-tests.sh

release: ## Universal release build
	swift build -c release --arch arm64 --arch x86_64

dmg: ## Build a distributable universal .dmg (dist/ShotEditor.dmg)
	./scripts/make-dmg.sh

cert: ## One-time: create a stable self-signed signing identity
	./scripts/create-signing-cert.sh

clean: ## Remove build products and artifacts
	rm -rf .build dist .test-artifacts ShotEditor.app
