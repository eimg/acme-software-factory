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

STYLE_RESET=""
STYLE_BOLD=""
STYLE_ACCENT=""
STYLE_SUCCESS=""
STYLE_MUTED=""
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  STYLE_RESET=$'\033[0m'
  STYLE_BOLD=$'\033[1m'
  STYLE_ACCENT=$'\033[38;5;39m'
  STYLE_SUCCESS=$'\033[38;5;35m'
  STYLE_MUTED=$'\033[38;5;244m'
fi

heading() {
  printf '\n%s%s%s%s\n' "$STYLE_BOLD" "$STYLE_ACCENT" "$1" "$STYLE_RESET"
}

profile_row() {
  printf '  %s%-12s%s %s\n' "$STYLE_MUTED" "$1" "$STYLE_RESET" "$2"
}

usage() {
  cat <<'EOF'
Managed service order:
  Identity 8316 -> Primer 8317 -> Prelude 8318 -> Issues 8320
  -> Projects 8321 -> Observability 8322 -> Steering 8323 -> Intel 8324

Target-scoped service:
  Helix 8319 runs separately from the repository it should change.

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
  NO_COLOR             Disable terminal colors when set

In local mode, missing service credentials trigger an interactive provisioning
prompt. Non-interactive startup fails with the exact provisioning command instead.
Use --provision-auth to deliberately provision or rotate credentials.

Helix remains outside this launcher because its working directory is part of
its execution context.
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
    "acme-obs/.env:ACME_OBS_HELIX_TOKEN" \
    "prelude/.env:ACME_STEERING_TOKEN" \
    "acme-todo/.helix/.env:ACME_STEERING_TOKEN" \
    "acme-issues/.env:ACME_STEERING_TOKEN" \
    "acme-projects/.env:ACME_STEERING_TOKEN" \
    "acme-steering/.env:ACME_STEERING_PRELUDE_TOKEN" \
    "acme-steering/.env:ACME_STEERING_HELIX_TOKEN" \
    "acme-steering/.env:ACME_STEERING_ISSUES_TOKEN" \
    "acme-steering/.env:ACME_STEERING_PROJECTS_TOKEN"
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
    heading "Stopping managed services"
    local index
    for ((index=${#PIDS[@]}-1; index>=0; index--)); do
      if kill -0 "${PIDS[$index]}" 2>/dev/null; then
        printf '  %s•%s %s\n' "$STYLE_MUTED" "$STYLE_RESET" "${NAMES[$index]}"
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
      printf '  %s✓%s %-20s %s\n' "$STYLE_SUCCESS" "$STYLE_RESET" "$name" "$url"
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

  printf '\n%s›%s %sStarting %s%s\n' "$STYLE_ACCENT" "$STYLE_RESET" "$STYLE_BOLD" "$name" "$STYLE_RESET"
  (
    cd "$ROOT_DIR/$directory"
    exec env "$@" npm run dev
  ) &
  local pid=$!
  PIDS+=("$pid")
  NAMES+=("$name")
  wait_for_health "$name" "$health_url" "$pid"
}

printf '\n%s%s◆ Acme Software Factory%s\n' "$STYLE_BOLD" "$STYLE_ACCENT" "$STYLE_RESET"
profile_row "Workspace" "$ROOT_DIR"
profile_row "Auth mode" "$AUTH_MODE"

heading "Startup profile"
profile_row "Identity" "$AUTH_MODE"
profile_row "Primer" "$PRIMER_AUTH_PROVIDER"
profile_row "Prelude" "$PRELUDE_AUTH_PROVIDER"
profile_row "Issues" "$AUTH_MODE"
profile_row "Projects" "$AUTH_MODE"
profile_row "Observer" "$AUTH_MODE"
profile_row "Steering" "$AUTH_MODE"
profile_row "Intel" "$AUTH_MODE"
if [[ "$AUTH_MODE" == "off" ]]; then
  profile_row "Purpose" "feature testing without sign-in"
else
  profile_row "Purpose" "authentication and role testing"
  profile_row "Credentials" "Helix API integrations use provisioned service tokens"
fi

heading "Starting managed services"

start_service "Acme Identity" "acme-identity" "$IDENTITY_URL/api/health" \
  "ACME_AUTH_MODE=$AUTH_MODE"

start_service "Primer" "primer" "http://127.0.0.1:8317/api/health" \
  "PRIMER_AUTH_PROVIDER=$PRIMER_AUTH_PROVIDER" \
  "PRIMER_AUTH_URL=$PRIMER_AUTH_URL"

start_service "Prelude" "prelude" "http://127.0.0.1:8318/api/health" \
  "PRELUDE_AUTH_PROVIDER=$PRELUDE_AUTH_PROVIDER" \
  "PRELUDE_AUTH_URL=$PRELUDE_AUTH_URL" \
  "ACME_STEERING_URL=http://127.0.0.1:8323"

start_service "Acme Issues" "acme-issues" "http://127.0.0.1:8320/api/health" \
  "ACME_AUTH_MODE=$AUTH_MODE" \
  "ACME_IDENTITY_URL=$IDENTITY_URL" \
  "ACME_STEERING_URL=http://127.0.0.1:8323"

start_service "Acme Projects" "acme-projects" "http://127.0.0.1:8321/api/health" \
  "ACME_AUTH_MODE=$AUTH_MODE" \
  "ACME_IDENTITY_URL=$IDENTITY_URL" \
  "ACME_STEERING_URL=http://127.0.0.1:8323"

start_service "Acme Observability" "acme-obs" "http://127.0.0.1:8322/api/health" \
  "ACME_AUTH_MODE=$AUTH_MODE" \
  "ACME_IDENTITY_URL=$IDENTITY_URL"

start_service "Acme Steering" "acme-steering" "http://127.0.0.1:8323/api/health" \
  "ACME_AUTH_MODE=$AUTH_MODE" \
  "ACME_IDENTITY_URL=$IDENTITY_URL" \
  "ACME_STEERING_PRELUDE_URL=http://127.0.0.1:8318" \
  "ACME_STEERING_HELIX_URL=http://127.0.0.1:8319" \
  "ACME_STEERING_ISSUES_URL=http://127.0.0.1:8320" \
  "ACME_STEERING_PROJECTS_URL=http://127.0.0.1:8321"

start_service "Acme Intel" "acme-intel" "http://127.0.0.1:8324/api/health" \
  "ACME_AUTH_MODE=$AUTH_MODE" \
  "ACME_IDENTITY_URL=$IDENTITY_URL" \
  "ACME_INTEL_OBS_URL=http://127.0.0.1:8322" \
  "ACME_INTEL_ISSUES_URL=http://127.0.0.1:8320" \
  "ACME_INTEL_HELIX_URL=http://127.0.0.1:8319" \
  "ACME_INTEL_STEERING_URL=http://127.0.0.1:8323"

heading "Ready"
profile_row "Identity" "$IDENTITY_URL"
profile_row "Primer" "http://127.0.0.1:8317"
profile_row "Prelude" "http://127.0.0.1:8318"
profile_row "Issues" "http://127.0.0.1:8320"
profile_row "Projects" "http://127.0.0.1:8321"
profile_row "Observer" "http://127.0.0.1:8322"
profile_row "Steering" "http://127.0.0.1:8323"
profile_row "Intel" "http://127.0.0.1:8324"

heading "Target-scoped service"
profile_row "Helix" "http://127.0.0.1:8319"
profile_row "Start from" "the target repository Helix should change"

printf '\n%sPress Ctrl-C to stop the managed services.%s\n' "$STYLE_MUTED" "$STYLE_RESET"

while true; do
  for index in "${!PIDS[@]}"; do
    if ! kill -0 "${PIDS[$index]}" 2>/dev/null; then
      echo "${NAMES[$index]} stopped unexpectedly." >&2
      exit 1
    fi
  done
  sleep 1
done
