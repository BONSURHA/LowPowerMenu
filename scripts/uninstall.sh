#!/usr/bin/env bash
set -euo pipefail

echo "==> Quitting LowPowerMenu if running..."
killall LowPowerMenu 2>/dev/null || true

TARGET_APP="/Applications/LowPowerMenu.app"
if [[ -d "${TARGET_APP}" ]]; then
    echo "==> Removing ${TARGET_APP}..."
    rm -rf "${TARGET_APP}"
    echo "==> Removed ${TARGET_APP}."
else
    echo "==> ${TARGET_APP} not found."
fi

TARGET_RULE="/private/etc/sudoers.d/lowpowermenu"
if [[ -f "${TARGET_RULE}" ]]; then
    echo "==> Removing privileged helper sudoers rule at ${TARGET_RULE} (requires sudo)..."
    sudo rm -f "${TARGET_RULE}"
    echo "==> Removed ${TARGET_RULE}."
else
    echo "==> Privileged helper rule not found at ${TARGET_RULE}."
fi

echo "==> Uninstallation complete."
