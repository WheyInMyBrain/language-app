# Build Stage
FROM node:24-alpine AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
# Run Vite build to output static files to /app/dist
RUN npm run build

# Production Static File Stage
FROM alpine:3.24
WORKDIR /app
COPY --from=builder /app/dist /app/dist
CMD ["sh", "-c", "echo 'Frontend static assets built successfully' && sleep infinity"]