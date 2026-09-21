#!/bin/bash
# Removes the Dexcom blood glucose bar widget.
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
PLUGIN_ID="dexcom-glucose"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
CONFIG_PATH="$HOME/.config/omarchy/dexcom.json"

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
  omarchy plugin remove "$PLUGIN_ID" --yes >/dev/null 2>&1 || true
  echo "Disabled and removed the $PLUGIN_ID plugin (Omarchy keeps a timestamped backup under ~/.config/omarchy/plugins/)."
else
  rm -rf "$PLUGIN_DIR"
  echo "Removed $PLUGIN_DIR"
fi

rm -f "$BIN_DIR/omarchy-dexcom-status"
echo "Removed $BIN_DIR/omarchy-dexcom-status"

echo ""
echo "Your config at $CONFIG_PATH and your Dexcom password in the system"
echo "keyring were both left in place. Remove them yourself if you're done:"
echo "  rm $CONFIG_PATH"
echo "  secret-tool clear service omarchy-dexcom-bar account dexcom-share"
