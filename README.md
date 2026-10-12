# Native macOS Swift Application Starter

<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="Application Icon" />
</p>

<p align="center">
  <strong>A lightweight, zero-dependency starter template for native macOS Swift applications with CLI build automation, retina DMG packaging, standalone unit testing, and GitHub release pipelines.</strong>
</p>

<p align="center">
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-GPL_v2.0-green?style=for-the-badge" alt="License: GPL v2.0" />
  </a>
  <img src="https://img.shields.io/badge/macOS-12.0+-lightgrey?style=for-the-badge&logo=apple" alt="macOS 12.0+" />
  <img src="https://img.shields.io/badge/Swift-5.7+-orange?style=for-the-badge&logo=swift" alt="Swift 5.7+" />
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#project-structure">Project Structure</a> •
  <a href="#customization">Customization</a> •
  <a href="#makefile-commands">Makefile Commands</a> •
  <a href="#license">License</a>
</p>

---

## Features

- ⚡ **Zero External Dependencies**: Pure native Swift and AppKit. No third-party package dependencies required to build and run.
- 🛠️ **CLI-First Tooling**: Build, code-sign, package, and test directly from the terminal without launching Xcode.
- 📦 **Automated Retina DMG Generator**: Creates customized, branded DMG installer packages with Retina background artwork, AppleScript layout positioning, and `/Applications` drag-and-drop symlinks.
- 🧪 **Standalone Native Test Suite**: Fast, lightweight command-line unit test runner that executes directly via `swiftc` without needing Xcode's XCTest platform.
- 🚀 **Automated Release Pipeline**: Semver version bumping, automated changelog generation from git history, and GitHub release creation via `gh`.
- 🌓 **Menu Bar & Window Ready**: Includes boilerplate code for both standard window applications and status bar / menu bar tray apps.

---

## Quick Start

### 1. Run the Application

Compile and launch the app in a single command:

```bash
make run
```

### 2. Run Unit Tests

Execute the native Swift unit test suite:

```bash
make test
```

### 3. Build a Distribution DMG

Generate a distributable macOS `.dmg` installer:

```bash
make dmg
open build/
```

---

## Project Structure

```text
├── Makefile                     # Build & lifecycle management targets
├── Package.swift                # Swift Package Manager manifest (IDE / SPM support)
├── VERSION                      # Current semver release version
├── LICENSE                      # Project license
├── README.md                    # Starter documentation
├── Resources/                   # App icons, status bar icons, and artwork
│   ├── AppIcon.icns             # Multi-resolution macOS icon bundle
│   ├── AppIcon.png              # High-res app icon (1024x1024)
│   ├── StatusBarIcon.png        # Template menu bar tray icon (18x18 & @2x)
│   └── dmg_background.png       # Styled DMG installer background
├── Sources/
│   └── App/
│       ├── Main.swift           # @main application entry point
│       ├── AppDelegate.swift    # Lifecycle, menus, windows, & status bar
│       └── AppConfig.swift      # Bundle metadata and runtime configuration
├── Tests/
│   └── AppTests/
│       ├── TestMain.swift       # Standalone CLI test harness
│       └── AppTests.swift       # Unit test specifications
└── scripts/
    ├── config.sh                # Centralized project configuration
    ├── build.sh                 # Compilation, Info.plist generation, and code signing
    ├── test.sh                  # Test compilation and execution
    ├── build_dmg.sh             # DMG creation with Finder view options
    ├── release.sh               # Version bumping, git tagging, and GitHub release
    ├── generate_app_icons.py    # Python icon renderer
    └── generate_dmg_background.py # Python Retina DMG background generator
```

---

## Customization

### 1. Customize App Name and Bundle Identifier

Edit [`scripts/config.sh`](scripts/config.sh) to set your project's details:

```bash
export APP_NAME="MyNewApp"
export BUNDLE_ID="com.mycompany.MyNewApp"
export MIN_MACOS_VERSION="12.0"
export LS_UI_ELEMENT="false" # Set to "true" for background / menu-bar-only apps
```

You can also override these on the fly via environment variables:

```bash
APP_NAME="CustomApp" make build
```

### 2. Add Your Code

- Place new Swift source files inside [`Sources/App/`](Sources/App/) (or any subdirectories under `Sources/`). `scripts/build.sh` automatically discovers and compiles all Swift files under `Sources/`.
- Add test suites under [`Tests/AppTests/`](Tests/AppTests/) and register them in [`Tests/AppTests/TestMain.swift`](Tests/AppTests/TestMain.swift).

### 3. Generate Custom Icons and DMG Artwork

Run the included Python generators to produce app icons and DMG backgrounds:

```bash
python3 scripts/generate_app_icons.py
python3 scripts/generate_dmg_background.py
```

---

## Makefile Commands

| Target | Description |
| :--- | :--- |
| `make help` | Display list of available targets |
| `make build` | Compile the `.app` bundle, generate `Info.plist`, and code-sign |
| `make run` | Compile and launch the application |
| `make launch` | Launch the compiled application without rebuilding |
| `make test` | Run the native Swift test runner |
| `make dmg` | Build a distributable DMG installer with custom layout |
| `make install` | Install the compiled `.app` into `/Applications` |
| `make clean` | Remove all build artifacts and temporary binaries |
| `make reset-cache` | Clear macOS LaunchServices and IconServices caches |
| `make release-dry-run` | Preview version bump and release steps (`make release-dry-run [version]`) |
| `make release` | Bump version, build DMG, create git tag, and publish release (`make release [version]`) |

---

## Releasing a New Version

To release a new version:

1. Preview changes with dry-run:
   ```bash
   make release-dry-run
   ```
2. Publish an auto-bumped patch release or specify an exact version:
   ```bash
   make release          # Bumps patch: 1.0.0 -> 1.0.1
   make release 1.1.0    # Explicit version: 1.1.0
   ```

The script will run the test suite, update [`VERSION`](VERSION), commit, tag, build the DMG, and publish a release via GitHub CLI (`gh`).

---

## License

This project is licensed under the [GNU General Public License v2.0](LICENSE).
