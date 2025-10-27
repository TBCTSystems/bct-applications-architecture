#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

CORE_SERVICES=(
  fluentd
  loki
  grafana
)

AGENT_SERVICES=(
  eca-acme-agent
  eca-est-agent
  target-server
  target-client
)

WITH_AGENTS=false
COMMAND=""
DEMO_MODE=false

print_usage() {
  cat <<'EOF'
Usage: scripts/observability.sh [command] [options]

Commands:
  up         Start Fluentd, Loki, Grafana (and optional agent demo stack)
  down       Stop and remove the observability containers
  status     Show docker compose status for the observability stack
  logs       Tail logs for Fluentd, Loki, and Grafana
  verify     Run scripts/verify-logging.sh (accepts --verbose/--quiet flags)
  demo       Full demo mode: start stack (with agents), verify, generate sample events

Options:
  --with-agents   Include eca-acme-agent, eca-est-agent, target-server, target-client
  -h, --help      Show this help message

Examples:
  ./scripts/observability.sh up --with-agents
  ./scripts/observability.sh status
  ./scripts/observability.sh verify -v
EOF
}

wait_for_compose_services() {
  local services=("$@")
  local timeout=120
  local interval=5

  for svc in "${services[@]}"; do
    printf 'Waiting for %s to report running...\n' "$svc"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
      local container
      container=$(cd "$PROJECT_DIR" && docker compose ps -q "$svc" 2>/dev/null || true)
      if [ -z "$container" ]; then
        sleep $interval
        elapsed=$((elapsed + interval))
        continue
      fi

      local status
      status=$(docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container" 2>/dev/null || true)
      case "$status" in
        *healthy*|running*)
          printf '  %s ready (%s)\n' "$svc" "$status"
          break
          ;;
      esac

      sleep $interval
      elapsed=$((elapsed + interval))
    done
  done
}

ensure_docker() {
  if ! command -v docker &> /dev/null; then
    echo "Docker is required. Install Docker Desktop or Engine." >&2
    exit 2
  fi
  if ! docker compose version &> /dev/null; then
    echo "Docker Compose v2 is required." >&2
    exit 2
  fi
}

run_verify() {
  cd "$PROJECT_DIR"
  chmod +x ./scripts/verify-logging.sh
  ./scripts/verify-logging.sh "${VERIFY_ARGS[@]}"
}

ARGS=("$@")
VERIFY_ARGS=()

# Argument parsing
while [[ $# -gt 0 ]]; do
  case $1 in
    up|down|status|logs|verify|demo)
      COMMAND=$1
      shift
      if [ "$COMMAND" = "verify" ]; then
        VERIFY_ARGS=("$@")
        break
      fi
      if [ "$COMMAND" = "demo" ]; then
        DEMO_MODE=true
      fi
      ;;
    --with-agents)
      WITH_AGENTS=true
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      print_usage >&2
      exit 2
      ;;
  esac
  if [[ -n "$COMMAND" && "$COMMAND" != "verify" ]]; then
    continue
  fi
  shift
done

if [ -z "$COMMAND" ]; then
  print_usage
  exit 1
fi

ensure_docker

SELECTED_SERVICES=("${CORE_SERVICES[@]}")
if [ "$WITH_AGENTS" = true ]; then
  SELECTED_SERVICES+=("${AGENT_SERVICES[@]}")
fi
if [ "$DEMO_MODE" = true ]; then
  WITH_AGENTS=true
  SELECTED_SERVICES=("${CORE_SERVICES[@]}" "${AGENT_SERVICES[@]}")
fi

case $COMMAND in
  up)
    cd "$PROJECT_DIR"
    docker compose up -d "${SELECTED_SERVICES[@]}"
    wait_for_compose_services "${SELECTED_SERVICES[@]}"
    ;;
  down)
    cd "$PROJECT_DIR"
    docker compose rm -sf "${SELECTED_SERVICES[@]}"
    ;;
  status)
    cd "$PROJECT_DIR"
    docker compose ps "${SELECTED_SERVICES[@]}"
    ;;
  logs)
    cd "$PROJECT_DIR"
    docker compose logs -f "${CORE_SERVICES[@]}"
    ;;
  verify)
    run_verify
    ;;
  demo)
    cd "$PROJECT_DIR"
    docker compose up -d "${SELECTED_SERVICES[@]}"
    wait_for_compose_services "${SELECTED_SERVICES[@]}"
    print_header "Running Log Flow Verification"
    run_verify
    print_header "Generating Sample Events"
    docker compose restart eca-acme-agent eca-est-agent >/dev/null
    docker compose exec eca-acme-agent touch /tmp/force-renew >/dev/null 2>&1 || true
    echo -e "${NC}Sample events generated. Force-renew triggered for ACME agent.${NC}"
    echo -e "${NC}Open Grafana: http://localhost:3000  (admin / eca-admin)${NC}"
    ;;
  *)
    print_usage
    exit 1
    ;;
 esac
