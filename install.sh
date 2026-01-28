#!/usr/bin/env bash
# reqdrive installer
# Usage: curl -fsSL https://raw.githubusercontent.com/user/reqdrive/main/install.sh | bash

set -euo pipefail

INSTALL_DIR="${REQDRIVE_INSTALL_DIR:-$HOME/.reqdrive}"

echo "Installing reqdrive to $INSTALL_DIR..."

# Check prerequisites
for tool in bash jq git gh claude; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: Required tool '$tool' not found. Please install it first." >&2
    exit 1
  fi
done

# Clone or update
if [ -d "$INSTALL_DIR" ]; then
  echo "Updating existing installation..."
  cd "$INSTALL_DIR" && git pull --ff-only
else
  echo "Cloning reqdrive..."
  git clone https://github.com/user/reqdrive.git "$INSTALL_DIR"
fi

# Make scripts executable
chmod +x "$INSTALL_DIR/bin/reqdrive"
chmod +x "$INSTALL_DIR/lib/"*.sh

# Detect shell and suggest PATH addition
SHELL_NAME="$(basename "${SHELL:-bash}")"
RC_FILE=""
case "$SHELL_NAME" in
  zsh)  RC_FILE="$HOME/.zshrc" ;;
  bash) RC_FILE="$HOME/.bashrc" ;;
  fish) RC_FILE="$HOME/.config/fish/config.fish" ;;
esac

PATH_LINE="export PATH=\"$INSTALL_DIR/bin:\$PATH\""
if [ "$SHELL_NAME" = "fish" ]; then
  PATH_LINE="set -gx PATH $INSTALL_DIR/bin \$PATH"
fi

if [ -n "$RC_FILE" ]; then
  if [ -f "$RC_FILE" ] && grep -qF "$INSTALL_DIR/bin" "$RC_FILE" 2>/dev/null; then
    echo "PATH already configured in $RC_FILE"
  else
    echo "" >> "$RC_FILE"
    echo "# reqdrive" >> "$RC_FILE"
    echo "$PATH_LINE" >> "$RC_FILE"
    echo "Added to $RC_FILE: $PATH_LINE"
  fi
fi

echo ""
echo "Installation complete!"
echo ""
echo "To get started:"
echo "  1. Restart your shell or run: source $RC_FILE"
echo "  2. cd into your project"
echo "  3. Run: reqdrive init"
