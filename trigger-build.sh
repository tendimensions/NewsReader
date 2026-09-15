#!/usr/bin/env bash
#
# Triggers a CodeMagic build for NewsReader via the REST API.
# Bash counterpart to trigger-build.ps1 — same flags, same app.info format.
#
# Usage:
#   ./trigger-build.sh -ApiKey "abc123" -AppId "def456" -Branch "main"
#   ./trigger-build.sh -ApiKey "abc123" -AppId "def456" -Branch "main" -Workflow ios-workflow
#
# -ApiKey / -AppId fall back to app.info (lines like $ApiKey=... / $AppId=...)
# next to this script when not passed on the command line.
#
# -Workflow must be one of:
#   ios-workflow       - iOS build & Firebase distribution (default)
#   android-workflow    - Android build & Firebase distribution
#   dev-workflow        - iOS + Android build & Firebase distribution
#
# Before hitting the API, this checks that pubspec.yaml's version and
# CHANGELOG.md's latest entry agree and that the entry actually has notes —
# CodeMagic's "Create release notes" step pulls straight from CHANGELOG.md,
# so a stale one ships silently otherwise. Pass -SkipChangelogCheck to bypass
# (e.g. re-triggering a build for a version already released).
#
# It also checks that the working tree is clean and that local HEAD matches
# origin/<Branch> — CodeMagic builds whatever commit is already on the remote
# branch, not your local working tree, so an unpushed commit builds silently
# stale code. Pass -SkipGitCheck to bypass.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

api_key=""
app_id=""
branch=""
workflow="ios-workflow"
skip_changelog_check=0
skip_git_check=0

usage() {
    echo "Usage: $0 -Branch <branch> [-ApiKey <key>] [-AppId <id>] [-Workflow ios-workflow|android-workflow|dev-workflow] [-SkipChangelogCheck] [-SkipGitCheck]" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -ApiKey) api_key="${2:-}"; shift 2 ;;
        -AppId) app_id="${2:-}"; shift 2 ;;
        -Branch) branch="${2:-}"; shift 2 ;;
        -Workflow) workflow="${2:-}"; shift 2 ;;
        -SkipChangelogCheck) skip_changelog_check=1; shift ;;
        -SkipGitCheck) skip_git_check=1; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

[[ -z "$branch" ]] && usage

case "$workflow" in
    ios-workflow|android-workflow|dev-workflow) ;;
    *)
        echo "Workflow must be one of: ios-workflow, android-workflow, dev-workflow" >&2
        exit 1
        ;;
esac

# Load ApiKey / AppId from app.info if not supplied on the command line.
info_file="$SCRIPT_DIR/app.info"
if [[ ( -z "$api_key" || -z "$app_id" ) && -f "$info_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^\$([A-Za-z_][A-Za-z0-9_]*)=(.+)$ ]]; then
            var="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            case "$var" in
                ApiKey) [[ -z "$api_key" ]] && api_key="$val" ;;
                AppId) [[ -z "$app_id" ]] && app_id="$val" ;;
            esac
        fi
    done < "$info_file"
fi

if [[ -z "$api_key" ]]; then
    echo "ApiKey is required (pass -ApiKey or set it in app.info)" >&2
    exit 1
fi
if [[ -z "$app_id" ]]; then
    echo "AppId is required (pass -AppId or set it in app.info)" >&2
    exit 1
fi

# Checks that pubspec.yaml's version and CHANGELOG.md's latest entry agree,
# and that the entry has actual notes under it — mirrors the extraction
# codemagic.yaml's "Create release notes" step uses, so this fails exactly
# when that step would silently produce stale or empty release notes.
check_release_notes() {
    local pubspec="$SCRIPT_DIR/pubspec.yaml"
    local changelog="$SCRIPT_DIR/CHANGELOG.md"

    if [[ ! -f "$pubspec" ]]; then
        echo "pubspec.yaml not found; skipping release notes check." >&2
        return 0
    fi
    if [[ ! -f "$changelog" ]]; then
        echo "CHANGELOG.md not found — add release notes before triggering a build." >&2
        return 1
    fi

    local pubspec_version
    pubspec_version=$(grep -m1 '^version:' "$pubspec" \
        | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
    if [[ -z "$pubspec_version" ]]; then
        echo "Could not parse a version from pubspec.yaml." >&2
        return 1
    fi

    local changelog_version
    changelog_version=$(grep -m1 -E '^## ' "$changelog" | sed -E 's/^## *//')
    if [[ -z "$changelog_version" ]]; then
        echo "CHANGELOG.md has no '## <version>' entry." >&2
        return 1
    fi

    if [[ "$changelog_version" != "$pubspec_version" ]]; then
        echo "Version mismatch: pubspec.yaml is $pubspec_version but CHANGELOG.md's latest entry is $changelog_version." >&2
        echo "Bump pubspec.yaml's version or add a CHANGELOG.md entry so they match." >&2
        return 1
    fi

    # Same extraction codemagic.yaml uses for release_notes.txt.
    local notes
    notes=$(sed '/^---$/q' "$changelog" | sed '$d' | tail -n +3 | sed '/^[[:space:]]*$/d')
    if [[ -z "$notes" ]]; then
        echo "CHANGELOG.md's latest entry ($changelog_version) has no notes under it." >&2
        return 1
    fi

    echo "Release notes OK: CHANGELOG.md's latest entry ($changelog_version) matches pubspec.yaml."
    return 0
}

# Checks that the working tree is committed and that local HEAD is exactly
# what origin/$branch has — CodeMagic clones the remote branch, so anything
# only sitting in the local working tree or in unpushed commits is invisible
# to the build no matter how recently it changed.
check_git_pushed() {
    local target_branch="$1"

    if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        echo "Not inside a git repository; skipping git push check." >&2
        return 0
    fi

    local dirty
    dirty=$(git -C "$SCRIPT_DIR" status --porcelain)
    if [[ -n "$dirty" ]]; then
        echo "Working tree has uncommitted changes:" >&2
        echo "$dirty" >&2
        return 1
    fi

    echo "Fetching origin/$target_branch to verify it's pushed..."
    if ! git -C "$SCRIPT_DIR" fetch origin "$target_branch" --quiet; then
        echo "Could not fetch origin/$target_branch — check the branch name and remote." >&2
        return 1
    fi

    local local_head remote_head
    local_head=$(git -C "$SCRIPT_DIR" rev-parse HEAD)
    remote_head=$(git -C "$SCRIPT_DIR" rev-parse "origin/$target_branch")

    if [[ "$local_head" != "$remote_head" ]]; then
        echo "Local HEAD ($local_head) doesn't match origin/$target_branch ($remote_head)." >&2
        echo "Commit and push before triggering a build, or CodeMagic will build stale code." >&2
        return 1
    fi

    echo "Git check OK: HEAD is committed and matches origin/$target_branch ($local_head)."
    return 0
}

if [[ "$skip_git_check" -eq 0 ]]; then
    if ! check_git_pushed "$branch"; then
        echo "" >&2
        echo "Aborting build trigger. Commit and push to origin/$branch, or pass -SkipGitCheck to bypass." >&2
        exit 1
    fi
else
    echo "Skipping git push check (-SkipGitCheck)."
fi

if [[ "$skip_changelog_check" -eq 0 ]]; then
    if ! check_release_notes; then
        echo "" >&2
        echo "Aborting build trigger. Fix CHANGELOG.md/pubspec.yaml, or pass -SkipChangelogCheck to bypass." >&2
        exit 1
    fi
else
    echo "Skipping release notes check (-SkipChangelogCheck)."
fi

echo "Triggering CodeMagic build..."
echo "  App:      $app_id"
echo "  Workflow: $workflow"
echo "  Branch:   $branch"
echo ""

body=$(jq -n --arg appId "$app_id" --arg workflowId "$workflow" --arg branch "$branch" \
    '{appId: $appId, workflowId: $workflowId, branch: $branch}')

response=$(curl -sS -w '\n%{http_code}' \
    -X POST "https://api.codemagic.io/builds" \
    -H "x-auth-token: $api_key" \
    -H "Content-Type: application/json" \
    -d "$body")

http_code="${response##*$'\n'}"
payload="${response%$'\n'*}"

if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
    build_id=$(echo "$payload" | jq -r '.buildId')
    echo "Build triggered successfully!"
    echo "  Build ID: $build_id"
    echo "  Track at: https://codemagic.io/app/$app_id/build/$build_id"
else
    echo "Failed to trigger build (HTTP $http_code)" >&2
    detail=$(echo "$payload" | jq -r '.message // empty' 2>/dev/null || true)
    [[ -n "$detail" ]] && echo "  $detail" >&2
    exit 1
fi
