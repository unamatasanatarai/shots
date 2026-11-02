# Release hooks for ggrel (sourced from the repository root; keep this file free of side effects).
#
#   gemini-release-notes | ggrel 1.0.1      # or: make release 1.0.1
#   ggrel 1.0.1 --notes "..." --dry-run      # preview only
#
# ggrel runs TEST_CMD, writes VERSION and commits it, then runs BUILD_CMD, tags, pushes and publishes
# RELEASE_ASSETS. ${version} below is replaced by ggrel with the target version (keep the single quotes).

APP_NAME="Shots"

TEST_CMD='./scripts/test-shots.sh && ./scripts/test-impact.sh'

# Build both Apple Silicon (arm64) and Intel (x86_64) DMG packages for release.
# build_dmg.sh all bumps BUILD_NUMBER once; committing it before ggrel tags
# ensures the tagged commit matches the build number embedded in both shipped DMGs.
BUILD_CMD='./scripts/build_dmg.sh all &&
  { git diff --quiet -- BUILD_NUMBER || git commit -m "chore(release): build $(cat BUILD_NUMBER) for v${version}" -- BUILD_NUMBER; }'

RELEASE_ASSETS=(
    'build/Shots-${version}-Silicon.dmg'
    'build/Shots-${version}-Intel.dmg'
)
