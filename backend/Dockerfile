# Build stage
FROM rust:1.98.1-bookworm AS builder
WORKDIR /app

COPY Cargo.toml Cargo.lock ./
# Create dummy main to cache dependency compilation
RUN mkdir src && echo "fn main() {}" > src/main.rs && cargo build --release && rm -rf src

COPY . .
# Update modified timestamp so Cargo rebuilds with real sources
RUN touch src/main.rs && cargo build --release

# Runner stage
FROM debian:bookworm-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/<your-binary-name> /app/server

EXPOSE 3000
CMD ["/app/server"]