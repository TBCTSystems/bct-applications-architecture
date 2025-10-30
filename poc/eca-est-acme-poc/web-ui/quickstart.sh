#!/bin/bash
# ============================================
# ECA Web UI - Quick Start Script
# ============================================
# This script helps you quickly build and start the Web UI

set -e

echo "=========================================="
echo "ECA Web UI - Quick Start"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Change to project root
cd "$(dirname "$0")/.."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running${NC}"
    echo "Please start Docker and try again"
    exit 1
fi

echo -e "${GREEN}Step 1: Checking dependencies...${NC}"
echo ""

# Check if observability stack is running
if ! docker compose ps loki | grep -q "Up"; then
    echo -e "${YELLOW}Loki is not running. Starting observability stack...${NC}"
    docker compose up -d fluentd loki grafana
    echo "Waiting for Loki to be healthy (30 seconds)..."
    sleep 30
else
    echo -e "${GREEN}Loki is running ✓${NC}"
fi

# Check if agents are running
if ! docker compose ps eca-acme-agent | grep -q "Up"; then
    echo -e "${YELLOW}Agents are not running. Starting agents...${NC}"
    docker compose up -d pki eca-acme-agent eca-est-agent
    echo "Waiting for agents to start (30 seconds)..."
    sleep 30
else
    echo -e "${GREEN}Agents are running ✓${NC}"
fi

echo ""
echo -e "${GREEN}Step 2: Building Web UI Docker image...${NC}"
echo ""
docker compose --profile optional build web-ui

echo ""
echo -e "${GREEN}Step 3: Starting Web UI service...${NC}"
echo ""
docker compose --profile optional up -d web-ui

echo ""
echo -e "${GREEN}Step 4: Waiting for Web UI to be healthy...${NC}"
echo ""

# Wait for health check
attempts=0
max_attempts=30

while [ $attempts -lt $max_attempts ]; do
    if docker compose ps web-ui | grep -q "healthy"; then
        echo -e "${GREEN}Web UI is healthy! ✓${NC}"
        break
    fi
    attempts=$((attempts + 1))
    echo -n "."
    sleep 1
done

echo ""
echo ""

if [ $attempts -eq $max_attempts ]; then
    echo -e "${RED}Web UI failed to become healthy${NC}"
    echo "Showing logs:"
    docker compose logs --tail=50 web-ui
    exit 1
fi

# Test health endpoint
echo -e "${GREEN}Step 5: Testing health endpoint...${NC}"
echo ""

if curl -s http://localhost:8888/api/health | grep -q "healthy"; then
    echo -e "${GREEN}Health check passed ✓${NC}"
else
    echo -e "${RED}Health check failed${NC}"
    exit 1
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Web UI is ready!${NC}"
echo "=========================================="
echo ""
echo "📊 Dashboard: http://localhost:8888"
echo "📈 Grafana:   http://localhost:3000 (admin/eca-admin)"
echo "🔍 Loki API:  http://localhost:3100"
echo ""
echo "Quick Commands:"
echo "  View logs:    docker compose logs -f web-ui"
echo "  Stop Web UI:  docker compose --profile optional stop web-ui"
echo "  Restart:      docker compose --profile optional restart web-ui"
echo "  Remove:       docker compose --profile optional down web-ui"
echo ""
echo "Test the dashboard:"
echo "  1. Open http://localhost:8888 in your browser"
echo "  2. Click 'Force Renewal' to test agent controls"
echo "  3. Toggle the theme with the sun/moon icon"
echo "  4. Filter logs by clicking 'acme' or 'est'"
echo ""
echo -e "${GREEN}Happy testing! 🚀${NC}"
echo ""
