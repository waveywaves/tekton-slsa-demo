# Makefile for Tekton SLSA Demo

APP_NAME := tekton-slsa-demo
VERSION := $(shell date +%Y%m%d-%H%M%S)
BUILD_TIME := $(shell date -Iseconds)
GO_VERSION := $(shell go version | cut -d' ' -f3)

.PHONY: all build test clean docker-build run

all: test build

build:
	@echo "Building $(APP_NAME)..."
	CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o $(APP_NAME) ./cmd/main.go

test:
	@echo "Running tests..."
	go test -v ./cmd/

clean:
	@echo "Cleaning up..."
	rm -f $(APP_NAME)
	docker rmi -f $(APP_NAME):$(VERSION) 2>/dev/null || true

docker-build:
	@echo "Building Docker image..."
	docker build \
		--build-arg BUILD_TIME="$(BUILD_TIME)" \
		--build-arg GO_VERSION="$(GO_VERSION)" \
		--build-arg APP_VERSION="$(VERSION)" \
		-t $(APP_NAME):$(VERSION) \
		-t $(APP_NAME):latest .

run: build
	@echo "Running $(APP_NAME)..."
	APP_VERSION=$(VERSION) BUILD_TIME="$(BUILD_TIME)" GO_VERSION="$(GO_VERSION)" ./$(APP_NAME)

dev-run:
	@echo "Running in development mode..."
	APP_VERSION=dev BUILD_TIME="$(BUILD_TIME)" GO_VERSION="$(GO_VERSION)" go run ./cmd/main.go

# Docker run commands
docker-run: docker-build
	@echo "Running Docker container..."
	docker run -it --rm -p 8080:8080 $(APP_NAME):latest

docker-test: docker-build
	@echo "Testing Docker container..."
	docker run --rm $(APP_NAME):latest ./$(APP_NAME) --version || echo "Version command not implemented"

# Help
help:
	@echo "Available targets:"
	@echo "  build       - Build the application binary"
	@echo "  test        - Run unit tests"
	@echo "  clean       - Clean build artifacts and Docker images"
	@echo "  docker-build - Build Docker image"
	@echo "  run         - Build and run the application"
	@echo "  dev-run     - Run in development mode (no build)"
	@echo "  docker-run  - Build and run Docker container"
	@echo "  docker-test - Build and test Docker container"
	@echo "  help        - Show this help message"