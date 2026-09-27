# Build stage
FROM rust:1.98.1-bookworm AS builder
WORKDIR /app

# Cache dependency layer
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && cargo build --release && rm -rf src

# Build real source code
COPY . .
RUN touch src/main.rs && cargo build --release

# Runner stage
FROM debian:bookworm-slim
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/backend /app/server

EXPOSE 3000

ENV RUST_LOG=info
CMD ["/app/server"]