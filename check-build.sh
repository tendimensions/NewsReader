#!/usr/bin/env bash
#
# Checks the status of a CodeMagic build via the REST API.
# Bash counterpart to check-build.ps1 — same flags, same app.info format.
#
# Usage:
#   ./check-build.sh -BuildId "69f6b16b1b22154a1810dd4a"
#   ./check-build.sh -BuildId "69f6b16b1b22154a1810dd4a" -Wait
#
# -ApiKey falls back to app.info (a line like $ApiKey=...) next to this
# script when not passed on the command line. -Wait polls every 30 seconds
# until the build reaches a terminal state.
#
# Requires GNU date (Linux) for timestamp parsing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

api_key=""
build_id=""
wait_flag=0

usage() {
    echo "Usage: $0 -BuildId <id> [-ApiKey <key>] [-Wait]" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -BuildId) build_id="${2:-}"; shift 2 ;;
        -ApiKey) api_key="${2:-}"; shift 2 ;;
        -Wait) wait_flag=1; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

[[ -z "$build_id" ]] && usage

# Load ApiKey from app.info if not supplied on the command line.
info_file="$SCRIPT_DIR/app.info"
if [[ -z "$api_key" && -f "$info_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^\$([A-Za-z_][A-Za-z0-9_]*)=(.+)$ ]]; then
            var="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            [[ "$var" == "ApiKey" ]] && api_key="$val"
        fi
    done < "$info_file"
fi

if [[ -z "$api_key" ]]; then
    echo "ApiKey is required (pass -ApiKey or set it in app.info)" >&2
    exit 1
fi

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RESET=$'\033[0m'

color_for_status() {
    case "$1" in
        finished) echo "$GREEN" ;;
        failed) echo "$RED" ;;
        canceled|timeout) echo "$YELLOW" ;;
        *) echo "$CYAN" ;;
    esac
}

is_terminal() {
    case "$1" in
        finished|failed|canceled|timeout|skipped) return 0 ;;
        *) return 1 ;;
    esac
}

# Fetches the build; prints "<json>\n<http_code>" on stdout.
fetch_build() {
    curl -sS -w '\n%{http_code}' -H "x-auth-token: $api_key" \
        "https://api.codemagic.io/builds/$build_id"
}

print_status_line() {
    local json="$1"
    local status workflow branch started finished app_id
    status=$(echo "$json" | jq -r '.build.status')
    workflow=$(echo "$json" | jq -r '.build.workflowName')
    branch=$(echo "$json" | jq -r '.build.branch')
    started=$(echo "$json" | jq -r '.build.startedAt // empty')
    finished=$(echo "$json" | jq -r '.build.finishedAt // empty')
    app_id=$(echo "$json" | jq -r '.build.appId')

    local started_fmt="-" finished_fmt="-" elapsed="-"
    if [[ -n "$started" ]]; then
        started_fmt=$(date -d "$started" +%H:%M:%S 2>/dev/null || echo "-")
        local end="$finished"
        [[ -z "$end" ]] && end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        [[ -n "$finished" ]] && finished_fmt=$(date -d "$finished" +%H:%M:%S 2>/dev/null || echo "-")

        local start_epoch end_epoch
        start_epoch=$(date -d "$started" +%s 2>/dev/null || echo "")
        end_epoch=$(date -d "$end" +%s 2>/dev/null || echo "")
        if [[ -n "$start_epoch" && -n "$end_epoch" ]]; then
            local span=$(( end_epoch - start_epoch ))
            elapsed=$(printf '%dm %02ds' $(( span / 60 )) $(( span % 60 )))
        fi
    fi

    local color; color=$(color_for_status "$status")
    echo ""
    echo "  Build ID:  $build_id"
    echo "  Workflow:  $workflow"
    echo "  Branch:    $branch"
    echo "  Status:    ${color}${status}${RESET}"
    echo "  Started:   $started_fmt"
    echo "  Finished:  $finished_fmt"
    echo "  Elapsed:   $elapsed"
    echo ""
    echo "  Track at: https://codemagic.io/app/$app_id/build/$build_id"
}

fetch_and_check() {
    local raw http_code json
    raw=$(fetch_build)
    http_code="${raw##*$'\n'}"
    json="${raw%$'\n'*}"
    if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
        echo "Failed to fetch build status (HTTP $http_code)" >&2
        exit 1
    fi
    echo "$json"
}

if [[ "$wait_flag" -eq 1 ]]; then
    echo "Polling build $build_id (Ctrl+C to stop)..."
    while true; do
        json=$(fetch_and_check)
        status=$(echo "$json" | jq -r '.build.status')
        timestamp=$(date +%H:%M:%S)
        color=$(color_for_status "$status")
        if is_terminal "$status"; then
            [[ "$status" == "finished" ]] && color="$GREEN" || color="$RED"
        fi
        echo "[$timestamp]  ${color}${status}${RESET}"

        if is_terminal "$status"; then
            print_status_line "$json"
            break
        fi
        sleep 30
    done
else
    json=$(fetch_and_check)
    print_status_line "$json"
fi
