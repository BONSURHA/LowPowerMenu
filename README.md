# LowPowerMenu

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat-square)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B-blue.svg?style=flat-square)](https://apple.com/macos)
[![License](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)

**LowPowerMenu** is a lightweight, native macOS menu bar utility designed to give you seamless control over macOS Low Power Mode (`pmset`) and real-time battery hardware telemetry. Built with a modern Liquid Glass popover interface, it operates with zero background overhead and requires no third-party daemons.

---

## Highlights & Features

- **Liquid Glass Interface**: Symmetrical, translucent macOS Sonoma/Sequoia menu popover styled with `.ultraThinMaterial` and subtle borders.
- **Darwin `pmset` Integration**: Native control of system low-power mode across Battery and AC power domains.
- **Intelligent Auto-Switching Policies**:
  - **Never**: Low Power Mode disabled.
  - **Always**: Low Power Mode permanently active.
  - **On Battery**: Low Power Mode enabled exclusively while running on battery power.
  - **On AC**: Low Power Mode enabled when connected to a power adapter.
- **Real-Time Battery Telemetry**:
  - **80% Limit / State of Charge**: Current battery percentage with dynamic Apple Health settings access.
  - **3-Column Micro-Stats**: Cycle count (`<value> <SF symbol>`), dynamic health percentage, and signed instantaneous power flow (`+W` charging, `-W` discharging).
- **Native Keyboard Shortcuts**:
  - `⌘⌥P`: Global hotkey to quickly toggle Low Power Mode from anywhere.
  - `1` – `4`: Fast policy selection directly inside the popover.
  - `⌘,`: Open Settings.
  - `⌘Q`: Quit application.
- **Pure Swift Architecture**: Modularized core business logic (`LowPowerCore`) isolated in an SPM package with 100% test coverage.

---

## Architecture

LowPowerMenu is architected around clean domain separation:

```
LowPowerMenu/
├── Core/                     # Pure Swift Package (LowPowerCore)
│   ├── Sources/LowPowerCore  # Models (PowerPolicy, SudoersHelper, Telemetry)
│   └── Tests/                # Comprehensive unit tests with zero AppKit/UI dependencies
├── LowPowerMenu/             # AppKit & SwiftUI Host Application
│   ├── AppDelegate.swift     # NSStatusItem lifecycle & global hotkey handling
│   ├── PowerMonitor.swift    # IOKit IOPMPowerSource & async pmset bridge
│   ├── NativeLiquidStripView # Liquid Glass popover SwiftUI interface
│   └── SettingsView.swift    # App settings & privileged helper management
└── scripts/                  # Automated build and installation utilities
```

---

## Privileged Helper & Security Model

Toggling system-wide Low Power Mode on macOS requires root privileges via Darwin's `/usr/bin/pmset`.

Rather than running a persistent root daemon or prompting for administrative credentials on every switch, LowPowerMenu uses a scoped `sudoers` rule located at:
```
/private/etc/sudoers.d/lowpowermenu
```
This rule permits only your local username to run `/usr/bin/pmset` without password prompts:
```
<username> ALL=(root) NOPASSWD: /usr/bin/pmset
```

The rule can be installed directly from the app's popover banner, the Settings window, or during command-line installation. It can be revoked at any time.

---

## Installation

### Automated Install (Recommended)

Clone the repository and run the automated installation script:

```bash
git clone https://github.com/nicolobossi/LowPowerMenu.git
cd LowPowerMenu
./scripts/install.sh
```

The script builds a Release configuration using Xcode and copies `LowPowerMenu.app` to your `/Applications` directory, optionally prompting to configure the privileged helper.

### Manual Xcode Build

You can also build and run directly using Xcode:

1. Open `LowPowerMenu.xcodeproj` in Xcode 15+.
2. Select the `LowPowerMenu` scheme and target `My Mac`.
3. Press `⌘B` to build or `⌘R` to run.

---

## Uninstallation

To remove the application and clean up any configured privileged helper rules:

```bash
./scripts/uninstall.sh
```

Or manually:

```bash
# Terminate the application
killall LowPowerMenu 2>/dev/null || true

# Remove the application bundle
rm -rf /Applications/LowPowerMenu.app

# Remove the sudoers rule
sudo rm -f /private/etc/sudoers.d/lowpowermenu
```

---

## Testing

Run unit tests for the core logic SPM package:

```bash
swift test --package-path Core
```

Verify macOS application build:

```bash
xcodebuild clean build -scheme LowPowerMenu -destination 'platform=macOS'
```

---

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.
