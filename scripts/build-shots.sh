#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
cd "$project_dir"

source "${script_dir}/config.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/${APP_NAME,,}"
mkdir -p "$cache_dir"

source "${script_dir}/build-common.sh"
parse_build_args "$@"

build_dir="$(arch_build_dir "$target_arch")"
app_name="Shots"
bundle_id="com.unamatasanatarai.Shots"
app_dir="${build_dir}/${app_name}.app"
contents_dir="${app_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"

# Start from an empty bundle: files left by earlier builds (or removed from Resources/) must not be sealed
# into the signed bundle and shipped
case "$app_dir" in
*/build/*.app | build/*.app) rm -rf -- "$app_dir" ;;
*) build_die "Refusing to clean unexpected bundle path: ${app_dir}" ;;
esac
mkdir -p "$macos_dir" "$resources_dir"

if [[ -d "Resources" ]]; then
    cp -R Resources/. "${resources_dir}/"
fi

if [[ -f "VERSION" ]]; then
    cp "VERSION" "${resources_dir}/VERSION"
fi
printf '%s\n' "$build_number" >"${resources_dir}/BUILD_NUMBER"

sources=()
while IFS= read -r file; do
    sources+=("$file")
done < <(find Sources/Shots -type f -name "*.swift" | sort)

printf '%s\n' "Compiling ${app_name} v${VERSION} (${target_arch}, Build ${BUILD_NUMBER}) (${#sources[@]} source files)..."
compile_swift "$target_arch" "${macos_dir}/${app_name}" "$cache_dir" "${sources[@]}"

printf '%s\n' "Generating ${app_name} Info.plist..."
cat <<EOF >"${contents_dir}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${app_name}</string>
    <key>CFBundleIdentifier</key>
    <string>${bundle_id}</string>
    <key>CFBundleName</key>
    <string>${app_name}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS_VERSION}</string>
    <key>LSUIElement</key>
    <${LS_UI_ELEMENT}/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>${COPYRIGHT}</string>
</dict>
</plist>
EOF

sign_and_register "$app_dir" "$bundle_id" "$target_arch"

printf '%s\n' "✅ Build complete:"
printf '%s\n' "   - ${app_dir}"
