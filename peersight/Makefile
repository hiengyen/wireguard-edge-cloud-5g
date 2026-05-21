.PHONY: all api agent broker app clean test help

all: api agent broker ## Build all Go binaries

api: ## Build peersight-api
	cd peersight-api && go build -o ../peersight-api ./cmd/api

agent: ## Build peersight-agent
	cd peersight-agent && go build -o ../peersight-agent ./cmd/agent

broker: ## Build peersight-broker
	cd peersight-broker && go build -o ../peersight-broker ./cmd/broker

app: ## Build peersight-app (Vue.js)
	cd peersight-app && npm install && npm run build

test: ## Run all tests
	cd peersight-api && go test ./...
	cd peersight-agent && go test ./...
	cd peersight-broker && go test ./...

clean: ## Remove build artifacts
	rm -f peersight-api peersight-agent peersight-broker
	rm -rf peersight-app/dist peersight-app/node_modules

docker-up: ## Start all services via Docker Compose
	docker compose up -d

docker-down: ## Stop all services
	docker compose down

docker-build: ## Build all Docker images
	docker compose build

db-migrate: ## Run database migrations
	psql "$${DATABASE_URL}" -f peersight-api/migrations/001_init.sql

lint-api: ## Lint the API code
	cd peersight-api && go vet ./...

lint-agent: ## Lint the Agent code
	cd peersight-agent && go vet ./...

lint-broker: ## Lint the Broker code
	cd peersight-broker && go vet ./...

lint: lint-api lint-agent lint-broker ## Lint all Go code

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
