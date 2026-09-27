# Build Stage
FROM node:24-alpine AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
# Run Vite build to output static files to /app/dist
RUN npm run build

RUN ls -la /app/dist

# Production Static File Stage
FROM alpine:3.24
WORKDIR /app
COPY --from=builder /app/dist /dist_source
# Copy /tmp/dist to /app/dist at container runtime so the named volume ALWAYS gets fresh files
CMD ["sh", "-c", "mkdir -p /app/dist && cp -r /dist_source/* /app/dist/ 2>/dev/null || cp -r /dist_source/. /app/dist/ && echo 'Assets copied successfully'"]