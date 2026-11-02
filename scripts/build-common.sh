#!/usr/bin/env bash

# Shared helpers for build-shots.sh, build-impact.sh and build_dmg.sh (sourced, never executed).
# Expects `project_dir` to be set and scripts/config.sh to be sourced first.

build_die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

# Canonical architecture name: Silicon, Intel, Universal or native. Unknown names are an error, so a typo
# never produces a DMG labeled with one architecture that contains another.
normalize_arch() {
    case "${1:-}" in
    "" | native | Native) printf '%s\n' "native" ;;
    arm64 | silicon | Silicon) printf '%s\n' "Silicon" ;;
    x86_64 | intel | Intel) printf '%s\n' "Intel" ;;
    universal | Universal) printf '%s\n' "Universal" ;;
    *) build_die "Unknown architecture '${1}'. Use one of: native, Silicon (arm64), Intel (x86_64), universal." ;;
    esac
}

# Where bundles for an architecture are built. Native builds live in build/ (used by `make run` and registered
# with LaunchServices); other architectures get their own folder so they never replace the native dev bundles.
arch_build_dir() {
    if [[ "$1" == "native" ]]; then
        printf '%s\n' "build"
    else
        printf '%s\n' "build/$1"
    fi
}

# Increments BUILD_NUMBER in the repository and prints the new value.
next_build_number() {
    local file="${project_dir}/BUILD_NUMBER" current="" next=1
    if [[ -f "$file" ]]; then
        IFS= read -r current <"$file" || true
        current="${current//[[:space:]]/}"
        if [[ "$current" =~ ^[0-9]+$ ]]; then
            next=$((current + 1))
        fi
    fi
    printf '%s\n' "$next" >"$file"
    printf '%s\n' "$next"
}

# Parses `[arch] [--build-number N]` for the app build scripts. Sets `target_arch`, `build_number` and exports
# BUILD_NUMBER. Without --build-number the repository BUILD_NUMBER is incremented. The number is passed as an
# argument (not an environment variable) so a value can never leak into later builds from the shell.
parse_build_args() {
    local raw_arch="${ARCH:-}" explicit_number=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --build-number)
            [[ -n "${2:-}" ]] || build_die "Missing value for --build-number"
            explicit_number="$2"
            shift 2
            ;;
        -*) build_die "Unknown option: $1" ;;
        *)
            raw_arch="$1"
            shift
            ;;
        esac
    done
    target_arch="$(normalize_arch "$raw_arch")"
    if [[ -n "$explicit_number" ]]; then
        [[ "$explicit_number" =~ ^[0-9]+$ ]] || build_die "Build number must be a positive integer: ${explicit_number}"
        build_number="$explicit_number"
    else
        build_number="$(next_build_number)"
    fi
    export BUILD_NUMBER="$build_number"
}

sdk_path() {
    local path
    path="$(xcrun --show-sdk-path 2>/dev/null)" || true
    [[ -n "$path" ]] || build_die "Failed to obtain SDK path from xcrun"
    printf '%s\n' "$path"
}

# compile_swift <arch> <output> <tmp_dir> <sources...>
# Universal builds compile both slices in parallel and merge them with lipo.
compile_swift() {
    local arch="$1" output="$2" tmp_dir="$3"
    shift 3
    local sdk
    sdk="$(sdk_path)"
    local flags=(-sdk "$sdk" -O -whole-module-optimization -Xlinker -dead_strip)

    case "$arch" in
    native) swiftc "${flags[@]}" "$@" -o "$output" ;;
    Silicon) swiftc -target "arm64-apple-macos${MIN_MACOS_VERSION}" "${flags[@]}" "$@" -o "$output" ;;
    Intel) swiftc -target "x86_64-apple-macos${MIN_MACOS_VERSION}" "${flags[@]}" "$@" -o "$output" ;;
    Universal)
        local slices_dir
        slices_dir="$(mktemp -d "${tmp_dir}/slices.XXXXXX")"
        swiftc -target "arm64-apple-macos${MIN_MACOS_VERSION}" "${flags[@]}" "$@" -o "${slices_dir}/arm64" &
        local arm_pid=$!
        swiftc -target "x86_64-apple-macos${MIN_MACOS_VERSION}" "${flags[@]}" "$@" -o "${slices_dir}/x86_64" &
        local x86_pid=$!
        local failed=0
        wait "$arm_pid" || failed=1
        wait "$x86_pid" || failed=1
        if [[ "$failed" == "1" ]]; then
            rm -rf "$slices_dir"
            build_die "Universal compile failed"
        fi
        lipo -create "${slices_dir}/arm64" "${slices_dir}/x86_64" -output "$output"
        rm -rf "$slices_dir"
        ;;
    *) build_die "compile_swift: unexpected architecture '${arch}'" ;;
    esac
}

# Signs the bundle; only native bundles are registered with LaunchServices. Registering extra copies with the
# same bundle ID makes macOS pick the wrong one (and System Settings show duplicate privacy entries).
sign_and_register() {
    local app_dir="$1" bundle_id="$2" arch="$3"
    printf '%s\n' "Signing $(basename "$app_dir")..."
    codesign --force --deep --sign - --requirements "=designated => identifier \"${bundle_id}\"" "$app_dir"

    local lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    if [[ "$arch" == "native" ]]; then
        printf '%s\n' "Refreshing macOS LaunchServices cache..."
        touch "$app_dir"
        "$lsregister" -f -R "$app_dir" >/dev/null 2>&1 || true
        qlmanage -r cache >/dev/null 2>&1 || true
    else
        "$lsregister" -u "$app_dir" >/dev/null 2>&1 || true
    fi
}

# Removes LaunchServices records of Shots/Impact copies made while packaging (build/<Arch>/, DMG staging folders,
# mounted installer volumes), keeping only the native dev bundles in build/ and installed apps. Finder and
# file copies register these copies automatically; left behind, they confuse "open by bundle ID" and privacy settings.
unregister_packaging_copies() {
    local lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    local build_root="${project_dir}/build/" path
    while IFS= read -r path; do
        case "$path" in
        "${build_root}Shots.app" | "${build_root}Impact.app") continue ;;
        "${build_root}"* | /Volumes/Shots*) "$lsregister" -u "$path" >/dev/null 2>&1 || true ;;
        esac
    done < <("$lsregister" -dump 2>/dev/null |
        sed -n -E 's/^path:[[:space:]]+(.*\/(Shots|Impact)\.app)( \(0x[0-9a-f]+\))?$/\1/p' | sort -u)
}
