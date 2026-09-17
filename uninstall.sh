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
echo "Your credentials file at $CONFIG_PATH was left in place (it holds your"
echo "Dexcom Share password). Remove it yourself if you no longer need it:"
echo "  rm $CONFIG_PATH"
