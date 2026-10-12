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

for arg in "$@"; do
    case "$arg" in
    --dry-run)
        dry_run=1
        ;;
    *)
        if [[ -z "$target_version" ]]; then
            target_version="$arg"
        fi
        ;;
    esac
done

current_version="${VERSION:-1.0.0}"

if [[ -n "$target_version" ]]; then
    target_version="${target_version#v}"
    if [[ ! "$target_version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
        printf '%s\n' "Error: Invalid version format '${target_version}'. Expected format like 1.1.0" >&2
        exit 1
    fi
    new_version="$target_version"
else
    # Auto-increment patch version
    major="${current_version%%.*}"
    rest="${current_version#*.}"
    if [[ "$rest" != "$current_version" && "$rest" =~ \. ]]; then
        minor="${rest%%.*}"
        patch="${rest#*.}"
    elif [[ "$rest" != "$current_version" ]]; then
        minor="$rest"
        patch="0"
    else
        minor="0"
        patch="0"
    fi

    if [[ "$patch" =~ ^[0-9]+$ ]]; then
        patch=$((patch + 1))
        new_version="${major}.${minor}.${patch}"
    else
        new_version="${current_version}.1"
    fi
fi

version="$new_version"
dmg_name="${APP_NAME}-${version}.dmg"
dmg_path="${build_dir}/${dmg_name}"

is_git_repo=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    is_git_repo=1
fi

if [[ "$dry_run" -eq 1 ]]; then
    printf '%s\n' "=================================================="
    printf '%s\n' "          Release Dry Run Preview                "
    printf '%s\n' "=================================================="
    printf '%s\n' "Target Application: ${APP_NAME}"
    printf '%s\n' "Version Bump:       v${current_version} -> v${version}"
    printf '%s\n' "Target Bundle:      ${BUNDLE_ID}"
    printf '%s\n' "DMG Artifact:       ${dmg_path}"
    printf '%s\n' "Git Enabled:        $([[ $is_git_repo -eq 1 ]] && echo 'Yes' || echo 'No (not a git repo)')"
    printf '%s\n' "Steps that would run:"
    printf '%s\n' "  1. Execute unit test suite (./scripts/test.sh)"
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
"${script_dir}/test.sh"

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
        release_notes="## ${APP_NAME} v${version}"$'\n\n'"Release for macOS ${MIN_MACOS_VERSION}+."
        gh release create "v${version}" "${dmg_path}" --title "${APP_NAME} v${version}" --notes "$release_notes" 2>/dev/null || true
    fi
fi

printf '%s\n' "✅ Release v${version} completed: ${dmg_path}"
