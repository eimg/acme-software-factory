#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTH_MODE="${ACME_AUTH_MODE:-}"
IDENTITY_URL="${ACME_IDENTITY_URL:-http://127.0.0.1:8316}"
START_TIMEOUT="${ACME_START_TIMEOUT:-30}"
PROVISION_AUTH=0

PIDS=()
NAMES=()
MISSING_AUTH=()
CLEANING_UP=0

usage() {
  cat <<'EOF'
Key component and port order:
  Identity 8316 -> Primer 8317 -> Prelude 8318 -> Helix 8319
  -> Issues 8320 -> Projects 8321 -> Observability 8322

Usage:
  ./start-acme.sh [--provision-auth]

Options:
  --provision-auth      Provision or rotate scoped suite service tokens before startup
  -h, --help            Show this help

Environment:
  ACME_AUTH_MODE       Suite mode: off | local (interactive menu when unset on a terminal)
  ACME_IDENTITY_URL    Identity URL (default: http://127.0.0.1:8316)
  PRELUDE_AUTH_PROVIDER Prelude auth adapter (acme-identity in local mode; standalone in off mode)
  PRELUDE_AUTH_URL      Prelude auth provider URL (default: identity URL)
  PRIMER_AUTH_PROVIDER Primer auth adapter (acme-identity in local mode; standalone in off mode)
  PRIMER_AUTH_URL       Primer auth provider URL (default: identity URL)
  ACME_START_TIMEOUT   Seconds to wait for each health check (default: 30)

In local mode, missing service credentials trigger an interactive provisioning
prompt. Non-interactive startup fails with the exact provisioning command instead.
Use --provision-auth to deliberately provision or rotate credentials.

This launcher skips Helix because it runs inside a target repository.
Press Ctrl-C to stop every service started by this script.
EOF
}

choose_auth_mode() {
  local choice
  while true; do
    cat <<'EOF'
Choose suite authentication mode:
  1) Off   - seamless feature testing as the development admin
  2) Local - Acme Identity sign-in, roles, and service-token enforcement
EOF
    read -r -p "Select mode [1]: " choice
    case "${choice:-1}" in
      1|off|Off|OFF)
        AUTH_MODE="off"
        return
        ;;
      2|local|Local|LOCAL)
        AUTH_MODE="local"
        return
        ;;
      *)
        echo "Please choose 1 (off) or 2 (local)." >&2
        echo
        ;;
    esac
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provision-auth)
      PROVISION_AUTH=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$PROVISION_AUTH" -eq 1 && -z "$AUTH_MODE" ]]; then
  AUTH_MODE="local"
fi

if [[ -z "$AUTH_MODE" ]]; then
  if [[ -t 0 ]]; then
    choose_auth_mode
  else
    # Preserve the historical default for scripts and other non-interactive callers.
    AUTH_MODE="local"
  fi
fi

if [[ "$AUTH_MODE" != "local" && "$AUTH_MODE" != "off" ]]; then
  echo "ACME_AUTH_MODE must be 'local' or 'off' (got '$AUTH_MODE')." >&2
  exit 2
fi

if [[ "$PROVISION_AUTH" -eq 1 && "$AUTH_MODE" != "local" ]]; then
  echo "--provision-auth requires ACME_AUTH_MODE=local (or an unset mode)." >&2
  exit 2
fi

DEFAULT_SUITE_AUTH_PROVIDER="acme-identity"
if [[ "$AUTH_MODE" == "off" ]]; then
  DEFAULT_SUITE_AUTH_PROVIDER="standalone"
fi
PRELUDE_AUTH_PROVIDER="${PRELUDE_AUTH_PROVIDER:-$DEFAULT_SUITE_AUTH_PROVIDER}"
PRELUDE_AUTH_URL="${PRELUDE_AUTH_URL:-$IDENTITY_URL}"
PRIMER_AUTH_PROVIDER="${PRIMER_AUTH_PROVIDER:-$DEFAULT_SUITE_AUTH_PROVIDER}"
PRIMER_AUTH_URL="${PRIMER_AUTH_URL:-$IDENTITY_URL}"

if ! [[ "$START_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "ACME_START_TIMEOUT must be a positive integer (got '$START_TIMEOUT')." >&2
  exit 2
fi

for command_name in node npm curl pgrep awk; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
done

env_has_value() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] && awk -F= -v expected="$key" '
    $1 == expected {
      value = substr($0, index($0, "=") + 1)
      if (length(value) > 0) found = 1
    }
    END { exit found ? 0 : 1 }
  ' "$file"
}

check_suite_auth() {
  local spec
  local file
  local key
  MISSING_AUTH=()
  for spec in \
    "acme-projects/.env:ACME_ISSUES_TOKEN" \
    "acme-issues/.env:ACME_HELIX_TOKEN" \
    "acme-issues/.env:ACME_PROJECTS_TOKEN" \
    "acme-todo/.helix/.env:HELIX_ISSUES_TOKEN" \
    "acme-todo/.helix/.env:HELIX_PRELUDE_TOKEN" \
    "acme-obs/.env:ACME_OBS_PRELUDE_TOKEN" \
    "acme-obs/.env:ACME_OBS_ISSUES_TOKEN" \
    "acme-obs/.env:ACME_OBS_PROJECTS_TOKEN" \
    "acme-obs/.env:ACME_OBS_HELIX_TOKEN"
  do
    file="${spec%%:*}"
    key="${spec#*:}"
    if ! env_has_value "$ROOT_DIR/$file" "$key"; then
      MISSING_AUTH+=("$file:$key")
    fi
  done
  [[ ${#MISSING_AUTH[@]} -eq 0 ]]
}

provision_suite_auth() {
  if [[ ! -d "$ROOT_DIR/acme-identity/node_modules" ]]; then
    echo "Dependencies are not installed for Acme Identity. Run npm install in acme-identity first." >&2
    exit 1
  fi
  echo "Provisioning scoped suite credentials..."
  (
    cd "$ROOT_DIR/acme-identity"
    npm run provision:suite-auth
  )
}

if [[ "$AUTH_MODE" == "local" ]]; then
  if [[ "$PROVISION_AUTH" -eq 1 ]]; then
    provision_suite_auth
  elif ! check_suite_auth; then
    echo "Missing local-auth credentials:"
    for missing in "${MISSING_AUTH[@]}"; do
      echo "  $missing"
    done
    if [[ -t 0 ]]; then
      read -r -p "Provision scoped suite credentials now? [Y/n] " provision_choice
      case "${provision_choice:-y}" in
        y|Y|yes|Yes|YES) provision_suite_auth ;;
        *) echo "Local startup cancelled; credentials were not changed." >&2; exit 2 ;;
      esac
    else
      echo "Provision them before non-interactive local startup:" >&2
      echo "  ./start-acme.sh --provision-auth" >&2
      exit 2
    fi
  fi
fi

terminate_tree() {
  local parent_pid="$1"
  local child_pid
  for child_pid in $(pgrep -P "$parent_pid" 2>/dev/null || true); do
    terminate_tree "$child_pid"
  done
  kill -TERM "$parent_pid" 2>/dev/null || true
}

cleanup() {
  if [[ "$CLEANING_UP" -eq 1 ]]; then
    return
  fi
  CLEANING_UP=1

  if [[ ${#PIDS[@]} -gt 0 ]]; then
    echo
    echo "Stopping Acme services..."
    local index
    for ((index=${#PIDS[@]}-1; index>=0; index--)); do
      if kill -0 "${PIDS[$index]}" 2>/dev/null; then
        echo "  stopping ${NAMES[$index]}"
        terminate_tree "${PIDS[$index]}"
      fi
    done
    wait "${PIDS[@]}" 2>/dev/null || true
  fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

wait_for_health() {
  local name="$1"
  local url="$2"
  local pid="$3"
  local attempt

  for ((attempt=1; attempt<=START_TIMEOUT; attempt++)); do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null || true
      echo "$name stopped before becoming healthy." >&2
      return 1
    fi
    if curl --fail --silent --show-error --max-time 1 "$url" >/dev/null 2>&1; then
      echo "  ready: $url"
      return 0
    fi
    sleep 1
  done

  echo "$name did not become healthy within ${START_TIMEOUT}s: $url" >&2
  return 1
}

start_service() {
  local name="$1"
  local directory="$2"
  local health_url="$3"
  shift 3

  if [[ ! -f "$ROOT_DIR/$directory/package.json" ]]; then
    echo "Missing service directory: $ROOT_DIR/$directory" >&2
    return 1
  fi
  if [[ ! -d "$ROOT_DIR/$directory/node_modules" ]]; then
    echo "Dependencies are not installed for $name. Run npm install in $directory first." >&2
    return 1
  fi

  echo "Starting $name..."
  (
    cd "$ROOT_DIR/$directory"
    exec env "$@" npm run dev
  ) &
  local pid=$!
  PIDS+=("$pid")
  NAMES+=("$name")
  wait_for_health "$name" "$health_url" "$pid"
}

echo "Acme suite root: $ROOT_DIR"
echo "Authentication mode: $AUTH_MODE"
echo "  Identity: $AUTH_MODE"
echo "  Primer:   $PRIMER_AUTH_PROVIDER"
echo "  Prelude:  $PRELUDE_AUTH_PROVIDER"
echo "  Issues:   $AUTH_MODE"
echo "  Projects: $AUTH_MODE"
echo "  Observer: $AUTH_MODE"
if [[ "$AUTH_MODE" == "off" ]]; then
  echo "  Purpose:  feature testing without sign-in"
else
  echo "  Purpose:  authentication and role testing"
  echo "  Note:     Helix API integrations require provisioned service tokens"
fi
echo

start_service "Acme Identity" "acme-identity" "$IDENTITY_URL/api/health" \
  "ACME_AUTH_MODE=$AUTH_MODE"

start_service "Primer" "primer" "http://127.0.0.1:8317/api/health" \
  "PRIMER_AUTH_PROVIDER=$PRIMER_AUTH_PROVIDER" \
  "PRIMER_AUTH_URL=$PRIMER_AUTH_URL"

start_service "Prelude" "prelude" "http://127.0.0.1:8318/api/health" \
  "PRELUDE_AUTH_PROVIDER=$PRELUDE_AUTH_PROVIDER" \
  "PRELUDE_AUTH_URL=$PRELUDE_AUTH_URL"

start_service "Acme Issues" "acme-issues" "http://127.0.0.1:8320/api/health" \
  "ACME_AUTH_MODE=$AUTH_MODE" \
  "ACME_IDENTITY_URL=$IDENTITY_URL"

start_service "Acme Projects" "acme-projects" "http://127.0.0.1:8321/api/health" \
  "ACME_AUTH_MODE=$AUTH_MODE" \
  "ACME_IDENTITY_URL=$IDENTITY_URL"

start_service "Acme Observability" "acme-obs" "http://127.0.0.1:8322/api/health" \
  "ACME_AUTH_MODE=$AUTH_MODE" \
  "ACME_IDENTITY_URL=$IDENTITY_URL"

echo
echo "Acme services are ready:"
echo "  Identity  $IDENTITY_URL"
echo "  Primer    http://127.0.0.1:8317"
echo "  Prelude   http://127.0.0.1:8318"
echo "  Helix     http://127.0.0.1:8319  (not launched; run inside target repo)"
echo "  Issues    http://127.0.0.1:8320"
echo "  Projects  http://127.0.0.1:8321"
echo "  Observer  http://127.0.0.1:8322"
echo
echo "Press Ctrl-C to stop all services."

while true; do
  for index in "${!PIDS[@]}"; do
    if ! kill -0 "${PIDS[$index]}" 2>/dev/null; then
      echo "${NAMES[$index]} stopped unexpectedly." >&2
      exit 1
    fi
  done
  sleep 1
done
