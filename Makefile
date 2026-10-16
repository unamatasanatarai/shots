.DEFAULT_GOAL := help
.PHONY: help kill build-shots build-impact dmg run-shots run-impact test-shots test-impact release revoke reset-cache clean

## help: Display this help message
help:
	@echo "Usage: make [target] [VERSION=x.y.z]"
	@echo ""
	@echo "Targets:"
	@awk '/^##/ { printf "  \033[36m%-20s\033[0m %s\n", substr($$2, 1, length($$2)-1), substr($$0, index($$0, $$3)) }' $(MAKEFILE_LIST)

## kill: Terminate running instances of both Shots and Impact
kill:
	@echo "==> Terminating existing Shots and Impact instances..."
	@killall "Shots" 2>/dev/null || pkill -x "Shots" 2>/dev/null || true
	@killall "Impact" 2>/dev/null || pkill -x "Impact" 2>/dev/null || true
	@sleep 0.2

## build-shots: Compile Shots.app only
build-shots:
	@./scripts/build-shots.sh

## build-impact: Compile Impact.app only
build-impact:
	@./scripts/build-impact.sh

## dmg: Build styled DMG distribution package for Shots and Impact
dmg:
	@./scripts/build_dmg.sh

## Run shots
run: kill build-impact run-shots

## run-shots: Kill running apps, rebuild shots, and launch Shots.app
run-shots: kill build-shots
	@echo "==> Launching Shots.app..."
	@open "build/Shots.app"

## run-impact: Kill running apps, rebuild impact, and launch Impact.app (optional: IMAGE=path)
run-impact: kill build-impact
	@echo "==> Launching Impact.app..."
	@if [ -n "$(IMAGE)" ]; then \
		open "build/Impact.app" --args "$$(cd "$$(dirname "$(IMAGE)")" && pwd)/$$(basename "$(IMAGE)")"; \
	else \
		open "build/Impact.app"; \
	fi

## test-shots: Run native Swift unit test suite for Shots
test-shots:
	@./scripts/test-shots.sh

## test-impact: Run Image Annotation Engine unit test suite for Impact
test-impact:
	@./scripts/test-impact.sh

# Capture positional arguments for release targets (e.g. make release 1.1.0)
ifeq ($(firstword $(MAKECMDGOALS)),release)
  RELEASE_TARGET_VERSION := $(word 2,$(MAKECMDGOALS))
  ifneq ($(RELEASE_TARGET_VERSION),)
    $(eval $(RELEASE_TARGET_VERSION):;@:)
  endif
  RELEASE_TARGET_SUMMARY := $(word 3,$(MAKECMDGOALS))
  ifneq ($(RELEASE_TARGET_SUMMARY),)
    $(eval $(RELEASE_TARGET_SUMMARY):;@:)
  endif
endif

## release: Release manually bumped version (make release <version>), build DMG, tag & publish
release:
	@./scripts/release.sh $(if $(VERSION),$(VERSION),$(RELEASE_TARGET_VERSION)) $(if $(SUMMARY),--summary "$(SUMMARY)",$(if $(RELEASE_TARGET_SUMMARY),--summary "$(RELEASE_TARGET_SUMMARY)",))

## revoke: Reset permissions (ScreenCapture, Accessibility) and clear macOS caches
revoke:
	@echo "==> Revoking macOS permissions for Shots and Impact..."
	@tccutil reset ScreenCapture com.local.Shots 2>/dev/null || true
	@tccutil reset Accessibility com.local.Shots 2>/dev/null || true
	@tccutil reset ScreenCapture com.local.Impact 2>/dev/null || true
	@tccutil reset Accessibility com.local.Impact 2>/dev/null || true
	@echo "==> Resetting macOS Icon and LaunchServices caches..."
	@touch "build/Shots.app" "build/Impact.app" 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "build/Shots.app" "build/Impact.app" 2>/dev/null || true
	@qlmanage -r 2>/dev/null || true
	@qlmanage -r cache 2>/dev/null || true
	@killall Dock 2>/dev/null || true
	@echo "✅ Revoke and cache reset complete."

reset-cache: revoke

## clean: Remove build artifacts and temporary files
clean:
	@echo "==> Cleaning build artifacts..."
	@rm -rf build .build /tmp/RunSwiftTests* /tmp/RunImpactTests*
	@echo "✅ Clean complete."
