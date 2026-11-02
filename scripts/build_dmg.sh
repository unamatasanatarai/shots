#!/usr/bin/env bash

# Builds the styled installer DMG(s) for Shots and Impact.
#
#   build_dmg.sh                 native build  -> build/Shots-<ver>.dmg
#   build_dmg.sh Silicon|Intel|universal       -> build/Shots-<ver>-<Arch>.dmg
#   build_dmg.sh all             Silicon + Intel DMGs
#
# Every run rebuilds the apps and bumps BUILD_NUMBER exactly once, so both apps in every DMG produced by one
# run share the same build number. Non-native bundles are built in build/<Arch>/ and never replace the native
# dev bundles in build/.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
cd "$project_dir"

source "${script_dir}/config.sh"
source "${script_dir}/build-common.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/${APP_NAME,,}"
mkdir -p "$cache_dir"

[[ $# -le 1 ]] || build_die "Usage: build_dmg.sh [native|Silicon|Intel|universal|all]"

requested="${1:-${ARCH:-}}"
case "$requested" in
all | both | All) targets=(Silicon Intel) ;;
*) targets=("$(normalize_arch "$requested")") ;;
esac

render_dmg_background() {
    [[ -f "${script_dir}/generate_dmg_background.py" ]] || return 0
    # Arrows are drawn by Impact's own ArrowLayer so the installer matches the app's arrow style
    local arrows_tool="${cache_dir}/dmg-arrows"
    local arrows_png="build/dmg_arrows@2x.png"
    mkdir -p build
    rm -f "$arrows_png"
    printf '%s\n' "Rendering DMG arrows with Impact's arrow style..."
    if ! swiftc -O -o "$arrows_tool" \
        Sources/Impact/Models/ArrowLayer.swift \
        Sources/Impact/Models/AnnotationLayer.swift \
        "${script_dir}/dmg-arrows/main.swift" || ! "$arrows_tool" "$arrows_png"; then
        printf '%s\n' "Warning: could not render Impact-style arrows; using fallback arrows" >&2
    fi
    printf '%s\n' "Generating styled DMG background..."
    python3 "${script_dir}/generate_dmg_background.py" "$arrows_png" || true
}

detach_shots_volumes() {
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ (/Volumes/Shots( [0-9]+)?)[[:space:]]*$ ]]; then
            hdiutil detach "${BASH_REMATCH[1]}" -force >/dev/null 2>&1 || true
        fi
    done < <(hdiutil info 2>/dev/null || true)
}

# make_dmg <arch>: packages the bundles already built for <arch> into a styled DMG
make_dmg() {
    local arch="$1" bundles_dir dmg_name
    bundles_dir="$(arch_build_dir "$arch")"
    if [[ "$arch" == "native" ]]; then
        dmg_name="Shots-${VERSION}.dmg"
    else
        dmg_name="Shots-${VERSION}-${arch}.dmg"
    fi
    local dmg_path="build/${dmg_name}"
    local tmp_dmg="build/tmp_rw_${arch}.dmg"
    local dmg_root="build/dmg_root_${arch}"

    detach_shots_volumes

    printf '%s\n' "Creating styled DMG package for Shots & Impact v${VERSION} (${arch}, build ${build_number})..."
    rm -rf "$dmg_root" "$tmp_dmg" "$dmg_path"
    mkdir -p "${dmg_root}/.background"

    if [[ -f "Resources/dmg_background.png" ]]; then
        cp "Resources/dmg_background.png" "${dmg_root}/.background/background.png"
        if [[ -f "Resources/dmg_background@2x.png" ]]; then
            tiffutil -cathidpicheck "Resources/dmg_background.png" "Resources/dmg_background@2x.png" -out "${dmg_root}/.background/background.tiff" >/dev/null 2>&1 || cp "Resources/dmg_background.png" "${dmg_root}/.background/background.tiff"
        else
            cp "Resources/dmg_background.png" "${dmg_root}/.background/background.tiff"
        fi
    fi

    cp -R "${bundles_dir}/Shots.app" "${dmg_root}/"
    cp -R "${bundles_dir}/Impact.app" "${dmg_root}/"
    ln -s /Applications "${dmg_root}/Applications"

    hdiutil create -volname "Shots" -srcfolder "$dmg_root" -format UDRW -ov "$tmp_dmg" >/dev/null

    local attach_output mount_point="" line
    attach_output="$(hdiutil attach -readwrite -noverify -noautoopen "$tmp_dmg" 2>/dev/null)"
    while IFS= read -r line; do
        if [[ "$line" =~ (/Volumes/Shots( [0-9]+)?)[[:space:]]*$ ]]; then
            mount_point="${BASH_REMATCH[1]}"
            break
        fi
    done <<<"$attach_output"

    if [[ -z "$mount_point" || ! -d "$mount_point" ]]; then
        build_die "Failed to identify disk image mount point"
    fi

    osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application "Finder"
    tell disk "Shots"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {300, 120, 1140, 580}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        if exists file ".background:background.tiff" then
            set background picture of theViewOptions to file ".background:background.tiff"
        end if
        set position of item "Shots.app" of container window to {150, 217}
        set position of item "Impact.app" of container window to {370, 217}
        set position of item "Applications" of container window to {690, 217}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

    sync
    hdiutil detach "$mount_point" >/dev/null 2>&1 || hdiutil detach -force "$mount_point" >/dev/null 2>&1

    hdiutil convert "$tmp_dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$dmg_path" >/dev/null
    rm -rf "$dmg_root" "$tmp_dmg"

    printf '%s\n' "✅ DMG created successfully: ${dmg_path}"
}

# One build number for every app and DMG produced by this run
build_number="$(next_build_number)"
export BUILD_NUMBER="$build_number"

# The background does not depend on the architecture: render it once
render_dmg_background

for arch in "${targets[@]}"; do
    printf '%s\n' "==> Building Shots and Impact (${arch}, build ${build_number})..."
    "${script_dir}/build-shots.sh" "$arch" --build-number "$build_number"
    "${script_dir}/build-impact.sh" "$arch" --build-number "$build_number"
    make_dmg "$arch"
done

unregister_packaging_copies
