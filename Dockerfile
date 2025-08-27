# Build stage
FROM golang:1.21-alpine AS builder

# Set build arguments for SLSA attestation
ARG BUILD_TIME
ARG GO_VERSION
ARG APP_VERSION=1.0.0

WORKDIR /app

# Copy go mod files
COPY go.mod ./
# Copy go.sum only if it exists (handles projects with no dependencies)
COPY go.su[m] ./ 
RUN go mod download

# Copy source code
COPY cmd/ ./cmd/

# Build the application with build info
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w" \
    -o tekton-slsa-demo \
    ./cmd/main.go

# Final stage
FROM alpine:3.18

# Add ca-certificates for HTTPS calls and create non-root user
RUN apk --no-cache add ca-certificates \
    && adduser -D -s /bin/sh appuser

WORKDIR /app

# Copy binary from builder stage
COPY --from=builder /app/tekton-slsa-demo .

# Set ownership
RUN chown appuser:appuser tekton-slsa-demo

# Switch to non-root user
USER appuser

# Set environment variables
ENV PORT=8080
ENV APP_VERSION=${APP_VERSION}
ENV BUILD_TIME=${BUILD_TIME}
ENV GO_VERSION=${GO_VERSION}

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run the application
CMD ["./tekton-slsa-demo"]