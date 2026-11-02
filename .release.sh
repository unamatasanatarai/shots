# Release hooks for ggrel (sourced from the repository root; keep this file free of side effects).
#
#   gemini-release-notes | ggrel 1.0.1      # or: make release 1.0.1
#   ggrel 1.0.1 --notes "..." --dry-run      # preview only
#
# ggrel runs TEST_CMD, writes VERSION and commits it, then runs BUILD_CMD, tags, pushes and publishes
# RELEASE_ASSETS. ${version} below is replaced by ggrel with the target version (keep the single quotes).

APP_NAME="Shots"

TEST_CMD='./scripts/test-shots.sh && ./scripts/test-impact.sh'

# Rebuild both apps after the VERSION bump: build_dmg.sh alone reuses any existing bundles in build/,
# which would ship the previous version's apps. The builds bump BUILD_NUMBER; committing it before ggrel
# tags makes the tagged commit match the build number inside the shipped apps.
BUILD_CMD='./scripts/build-shots.sh && ./scripts/build-impact.sh && ./scripts/build_dmg.sh &&
  { git diff --quiet -- BUILD_NUMBER || git commit -m "chore(release): build $(cat BUILD_NUMBER) for v${version}" -- BUILD_NUMBER; }'

RELEASE_ASSETS=('build/Shots-${version}.dmg')
