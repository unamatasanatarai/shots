#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
cd "$project_dir"

source "${script_dir}/config.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/impact"
mkdir -p "$cache_dir"

sdk_file="${cache_dir}/sdk_path.tmp"
xcrun --show-sdk-path >"$sdk_file" 2>/dev/null
if [[ ! -s "$sdk_file" ]]; then
    rm -f "$sdk_file"
    printf '%s\n' "Error: Failed to locate macOS SDK via xcrun" >&2
    exit 1
fi
IFS= read -r sdk_path <"$sdk_file"
rm -f "$sdk_file"

test_dir="${XDG_RUNTIME_DIR:-/tmp}"
test_bin="${test_dir}/RunImpactTests_${RANDOM}"
trap 'rm -f "$test_bin"' EXIT INT TERM

# Collect Impact app sources excluding entry points with @main (e.g. ImpactMain.swift)
sources=()
while IFS= read -r file; do
    if ! grep -q "@main" "$file" 2>/dev/null; then
        sources+=("$file")
    fi
done < <(find Sources/Impact -type f -name "*.swift" | sort)

impact_tests=(
    "Tests/AppTests/EditorTests.swift"
    "Tests/EditorTestMain.swift"
)

printf '%s\n' "Compiling Impact test suite..."
swiftc -sdk "$sdk_path" \
    "${sources[@]}" \
    "${impact_tests[@]}" \
    -o "$test_bin"

test_status=0
"$test_bin" || test_status=$?
rm -f "$test_bin"

if [[ "$test_status" -ne 0 ]]; then
    printf '%s\n' "Error: Impact unit tests failed with status ${test_status}" >&2
    exit "$test_status"
fi
