#!/bin/bash
# Installs the Dexcom blood glucose bar widget for Omarchy.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
PLUGIN_ID="dexcom-glucose"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
CONFIG_PATH="$HOME/.config/omarchy/dexcom.json"

mkdir -p "$BIN_DIR"
cp "$REPO_DIR/omarchy-dexcom-status" "$BIN_DIR/"
chmod +x "$BIN_DIR/omarchy-dexcom-status"
echo "Installed omarchy-dexcom-status to $BIN_DIR"

case ":$PATH:" in
*":$BIN_DIR:"*) ;;
*) echo "Warning: $BIN_DIR is not on your PATH. Add it in your shell profile." ;;
esac

mkdir -p "$PLUGIN_DIR"
cp "$REPO_DIR/dexcom-glucose/manifest.json" "$REPO_DIR/dexcom-glucose/BarWidget.qml" "$REPO_DIR/dexcom-glucose/Panel.qml" "$PLUGIN_DIR/"
echo "Installed plugin to $PLUGIN_DIR"

if [[ ! -f "$CONFIG_PATH" ]]; then
  mkdir -p "$(dirname "$CONFIG_PATH")"
  cat > "$CONFIG_PATH" <<'EOF'
{
  "username": "",
  "region": "us",
  "highThreshold": 180,
  "lowThreshold": 70
}
EOF
  chmod 600 "$CONFIG_PATH"
  echo "Created $CONFIG_PATH (permissions 600)."
else
  echo "$CONFIG_PATH already exists, leaving it alone."
fi

if command -v omarchy >/dev/null 2>&1; then
  if omarchy plugin validate "$PLUGIN_DIR" >/dev/null 2>&1; then
    # The running shell won't know about a just-copied plugin id until it
    # rescans its plugins directory -- without this, enable fails with
    # "unknown plugin" even though the files are in place.
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
    if enable_output=$(omarchy plugin enable "$PLUGIN_ID" --section right 2>&1); then
      echo "Enabled $PLUGIN_ID in the bar (right section)."
    else
      echo "Warning: couldn't enable $PLUGIN_ID automatically: $enable_output"
      echo "Run this yourself: omarchy plugin enable $PLUGIN_ID --section right"
    fi
  else
    echo "Warning: plugin failed validation -- run 'omarchy plugin validate $PLUGIN_DIR' to see why."
  fi
else
  echo "'omarchy' command not found -- enable the plugin manually once it's on an Omarchy system."
fi

echo "Done. Left-click the widget in the bar to set up your Dexcom Share account -- your password is stored in the system keyring, not in $CONFIG_PATH."
