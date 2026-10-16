#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
cd "$project_dir"

source "${script_dir}/config.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/${APP_NAME,,}"
mkdir -p "$cache_dir"

build_dir="build"
dry_run=0
target_version=""
target_summary="${SUMMARY:-${NOTES:-}}"

while [[ $# -gt 0 ]]; do
    case "$1" in
    --dry-run)
        dry_run=1
        shift
        ;;
    --summary | -m | --notes)
        if [[ -n "${2:-}" ]]; then
            target_summary="$2"
            shift 2
        else
            shift
        fi
        ;;
    -*)
        printf '%s\n' "Unknown option: $1" >&2
        exit 1
        ;;
    *)
        if [[ -z "$target_version" ]]; then
            target_version="$1"
        elif [[ -z "$target_summary" ]]; then
            target_summary="$1"
        fi
        shift
        ;;
    esac
done

current_version="${VERSION:-1.0.0}"

# Demand manual version bump
if [[ -z "$target_version" ]]; then
    printf '%s\n' "Error: Manual version bumping is required." >&2
    printf '%s\n' "Please specify the version explicitly: make release <version> (e.g., make release 1.0.1) or ./scripts/release.sh <version>" >&2
    printf '%s\n' "Current repository version is v${current_version}" >&2
    exit 1
fi

target_version="${target_version#v}"
if [[ ! "$target_version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    printf '%s\n' "Error: Invalid version format '${target_version}'. Expected format like 1.0.1 or 1.1.0" >&2
    exit 1
fi

if git rev-parse "v${target_version}" >/dev/null 2>&1; then
    printf '%s\n' "Error: Tag v${target_version} already exists. Please specify a new version." >&2
    exit 1
fi

version="$target_version"
dmg_name="${APP_NAME}-${version}.dmg"
dmg_path="${build_dir}/${dmg_name}"

is_git_repo=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    is_git_repo=1
fi

# Resolve web repository URL from git remote
repo_web_url=""
if [[ "$is_git_repo" -eq 1 ]]; then
    remote_url="$(git config --get remote.origin.url 2>/dev/null || true)"
    repo_path="${remote_url%.git}"
    if [[ "$repo_path" =~ github\.com[:/](.+)$ ]]; then
        github_repo="${BASH_REMATCH[1]}"
        repo_web_url="https://github.com/${github_repo}"
    fi
fi

# Determine one-sentence summary and commit hash
commit_full="$(git rev-parse HEAD 2>/dev/null || echo '')"
commit_hash="$(git rev-parse --short HEAD 2>/dev/null || echo '')"

if [[ -n "$target_summary" ]]; then
    summary="$target_summary"
else
    commit_subject="$(git log -1 --pretty=%s HEAD 2>/dev/null || echo 'Release update')"
    # If HEAD is a release bump commit, look at HEAD~1 for the feature summary
    if [[ "$commit_subject" =~ ^chore\(release\) ]]; then
        target_commit="$(git log -1 --pretty=%H HEAD~1 2>/dev/null || echo "$commit_full")"
        commit_hash="$(git log -1 --pretty=%h "$target_commit" 2>/dev/null || echo "$commit_hash")"
        commit_full="$target_commit"
        commit_subject="$(git log -1 --pretty=%s "$target_commit" 2>/dev/null || echo "$commit_subject")"
    fi
    summary="$commit_subject"
fi

# Release notes format: one sentence summary - commit hash & link
if [[ -n "$repo_web_url" && -n "$commit_hash" ]]; then
    commit_link="${repo_web_url}/commit/${commit_full}"
    release_notes="${summary} - [${commit_hash}](${commit_link})"
elif [[ -n "$commit_hash" ]]; then
    release_notes="${summary} - ${commit_hash}"
else
    release_notes="${summary}"
fi

if [[ "$dry_run" -eq 1 ]]; then
    printf '%s\n' "=================================================="
    printf '%s\n' "          Release Dry Run Preview                "
    printf '%s\n' "=================================================="
    printf '%s\n' "Target Application: ${APP_NAME}"
    printf '%s\n' "Version:            v${current_version} -> v${version}"
    printf '%s\n' "Release Notes:      ${release_notes}"
    printf '%s\n' "Target Bundle:      ${BUNDLE_ID}"
    printf '%s\n' "DMG Artifact:       ${dmg_path}"
    printf '%s\n' "Git Enabled:        $([[ $is_git_repo -eq 1 ]] && echo 'Yes' || echo 'No (not a git repo)')"
    printf '%s\n' "Steps that would run:"
    printf '%s\n' "  1. Execute unit test suites (./scripts/test-shots.sh & ./scripts/test-impact.sh)"
    printf '%s\n' "  2. Update VERSION to ${version}"
    if [[ "$is_git_repo" -eq 1 ]]; then
        printf '%s\n' "  3. Commit VERSION and create git tag v${version}"
        printf '%s\n' "  4. Push tag to remote git origin"
        printf '%s\n' "  5. Build DMG installer package"
        printf '%s\n' "  6. Publish GitHub Release via gh CLI"
    else
        printf '%s\n' "  3. Build DMG installer package"
    fi
    printf '%s\n' "=================================================="
    exit 0
fi

printf '%s\n' "Running unit tests before release..."
"${script_dir}/test-shots.sh"
"${script_dir}/test-impact.sh"

printf '%s\n' "Updating VERSION to ${version}..."
printf '%s\n' "$version" >"VERSION"
export VERSION="$version"

if [[ "$is_git_repo" -eq 1 ]]; then
    git diff --quiet "VERSION" || {
        git add "VERSION"
        git commit -m "chore(release): bump version to v${version}"
        current_branch="$(git rev-parse --abbrev-ref HEAD)"
        git push origin "$current_branch" 2>/dev/null || true
    }
fi

printf '%s\n' "Building release DMG..."
"${script_dir}/build_dmg.sh"

if [[ "$is_git_repo" -eq 1 ]]; then
    if ! git rev-parse "v${version}" >/dev/null 2>&1; then
        git tag -a "v${version}" -m "Release ${APP_NAME} v${version}"
        git push origin "v${version}" 2>/dev/null || true
    fi

    if command -v gh >/dev/null 2>&1; then
        printf '%s\n' "Publishing GitHub release v${version}..."
        printf '%s\n' "Release notes: ${release_notes}"
        gh release create "v${version}" "${dmg_path}" --title "${APP_NAME} v${version}" --notes "$release_notes" 2>/dev/null || true
    fi
fi

printf '%s\n' "✅ Release v${version} completed: ${dmg_path}"
