.PHONY: help run build deploy provision tidy fmt clean

APP := terminal-app

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

run: ## Run locally on port 2222 (ssh -p 2222 localhost)
	go run .

build: ## Build a local binary into ./dist
	@mkdir -p dist
	go build -o dist/$(APP) .

deploy: ## Build a static binary and ship it to the VPS
	bash scripts/deploy.sh

provision: ## One-time: install the systemd service on the VPS
	bash scripts/provision.sh

tidy: ## go mod tidy
	go mod tidy

fmt: ## gofmt the tree
	gofmt -w .

clean: ## Remove build artifacts
	rm -rf dist
