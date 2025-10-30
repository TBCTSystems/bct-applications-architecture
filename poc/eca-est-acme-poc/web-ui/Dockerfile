# ============================================
# Multi-stage Dockerfile for ECA Web UI
# ============================================
# Stage 1: Build frontend with Vite
# Stage 2: Production runtime with Node.js

# --------------------------------------------
# Stage 1: Build Frontend
# --------------------------------------------
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production --ignore-scripts && \
    npm ci --only=development --ignore-scripts

# Copy source code
COPY . .

# Build frontend
RUN npm run build

# --------------------------------------------
# Stage 2: Production Runtime
# --------------------------------------------
FROM node:20-alpine

# Install Docker CLI for agent control functionality
RUN apk add --no-cache docker-cli

WORKDIR /app

# Copy package files and install production dependencies only
COPY package*.json ./
RUN npm ci --only=production --ignore-scripts

# Copy built frontend from builder stage
COPY --from=builder /app/dist ./dist

# Copy server code
COPY server ./server

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 && \
    chown -R nodejs:nodejs /app

USER nodejs

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "require('http').get('http://localhost:8080/api/health', (r) => { process.exit(r.statusCode === 200 ? 0 : 1); });"

# Set production environment
ENV NODE_ENV=production
ENV PORT=8080

# Start server
CMD ["node", "server/index.js"]
