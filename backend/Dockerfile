# Build stage
FROM rust:1.98.1-bookworm AS builder
WORKDIR /app

# Install build prerequisites
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# 1. Cache dependencies properly
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && \
    echo "fn main() {}" > src/main.rs && \
    cargo build --release && \
    rm -rf src target/release/deps/$(cargo metadata --no-deps --format-version 1 | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)*

# 2. Build application source
COPY . .
RUN cargo build --release

# Runner stage
FROM debian:bookworm-slim
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libsqlite3-0 \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Find and copy the compiled binary dynamically from release
COPY --from=builder /app/target/release/backend /app/server

# Create storage directory inside container
RUN mkdir -p /app/storage

ENV RUST_LOG=info
ENV PORT=3000
ENV STORAGE_DIR=/app/storage

EXPOSE 3000

CMD ["/app/server"]