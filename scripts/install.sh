#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Building LowPowerMenu (Release configuration)..."
cd "${ROOT_DIR}"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme LowPowerMenu -configuration Release clean build

# Locate built application
BUILT_APP=$(find ~/Library/Developer/Xcode/DerivedData -name "LowPowerMenu.app" -path "*/Release/*" -type d 2>/dev/null | head -n 1)

if [[ -z "${BUILT_APP}" || ! -d "${BUILT_APP}" ]]; then
    if [[ -d "${ROOT_DIR}/build/Release/LowPowerMenu.app" ]]; then
        BUILT_APP="${ROOT_DIR}/build/Release/LowPowerMenu.app"
    elif [[ -d "${ROOT_DIR}/build/Build/Products/Release/LowPowerMenu.app" ]]; then
        BUILT_APP="${ROOT_DIR}/build/Build/Products/Release/LowPowerMenu.app"
    fi
fi

if [[ -z "${BUILT_APP}" || ! -d "${BUILT_APP}" ]]; then
    echo "Error: Could not locate built LowPowerMenu.app." >&2
    exit 1
fi

echo "==> Found build at: ${BUILT_APP}"
echo "==> Quitting any running instance of LowPowerMenu..."
killall LowPowerMenu 2>/dev/null || true

echo "==> Installing to /Applications/LowPowerMenu.app..."
rm -rf /Applications/LowPowerMenu.app
cp -R "${BUILT_APP}" /Applications/LowPowerMenu.app

echo "==> LowPowerMenu installed successfully to /Applications/LowPowerMenu.app"

# Helper installation prompt
TARGET_RULE="/private/etc/sudoers.d/lowpowermenu"
if [[ -f "${TARGET_RULE}" ]]; then
    echo "==> Privileged helper rule already exists at ${TARGET_RULE}."
else
    echo ""
    echo "LowPowerMenu can automatically switch macOS Low Power Mode using pmset."
    echo "This requires a privileged helper rule in /private/etc/sudoers.d/lowpowermenu."
    read -r -p "Would you like to install the privileged helper now? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            CURRENT_USER=$(id -un)
            TEMP_RULE=$(mktemp /tmp/lowpowermenu_sudoers.XXXXXX)
            echo "${CURRENT_USER} ALL=(root) NOPASSWD: /usr/bin/pmset" > "${TEMP_RULE}"
            
            echo "Installing sudoers rule (requires sudo credentials)..."
            if sudo install -m 0440 -o root -g wheel "${TEMP_RULE}" "${TARGET_RULE}" && sudo visudo -cf "${TARGET_RULE}"; then
                rm -f "${TEMP_RULE}"
                echo "==> Helper installed successfully!"
            else
                rm -f "${TEMP_RULE}"
                echo "Warning: Failed to install privileged helper. You can install it later from the app Settings." >&2
            fi
            ;;
        *)
            echo "Skipping helper setup. You can configure it anytime in the app Settings."
            ;;
    esac
fi

echo ""
echo "Installation complete! You can open the app with:"
echo "  open /Applications/LowPowerMenu.app"
