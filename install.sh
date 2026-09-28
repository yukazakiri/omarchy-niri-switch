#!/bin/bash
# Install local.niri-switch. Idempotent — safe to re-run.
# System files (needs root via sudo/pkexec):
#   /usr/local/share/wayland-sessions/omarchy-niri.desktop  (uwsm Niri session)
#   /usr/local/bin/local-niri-switch-set-session             (SDDM target setter)
# User files (no privileges):
#   ~/.config/illogical-impulse/actions/switch-to-omarchy    (iNiR "/switch" command)
#   ~/.local/share/applications/switch-to-*.desktop          (launcher search entries)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

elevate() {
  if [ -t 0 ]; then sudo "$@"; else pkexec "$@"; fi
}

elevate cp "$SRC/examples/omarchy-niri.desktop.example" \
  /usr/local/share/wayland-sessions/omarchy-niri.desktop
elevate cp "$SRC/examples/local-niri-switch-set-session" \
  /usr/local/bin/local-niri-switch-set-session
elevate chmod 755 /usr/local/bin/local-niri-switch-set-session

echo "Installed system files."

# --- User files: iNiR "/switch" command + launcher search entries ---
mkdir -p "$HOME/.config/illogical-impulse/actions" "$HOME/.local/share/applications"
cp "$SRC/inir/actions/switch-to-omarchy" "$HOME/.config/illogical-impulse/actions/switch-to-omarchy"
chmod +x "$HOME/.config/illogical-impulse/actions/switch-to-omarchy"
sed "s|\$HOME|$HOME|g" "$SRC/applications/switch-to-omarchy.desktop" \
  > "$HOME/.local/share/applications/switch-to-omarchy.desktop"
sed "s|\$HOME|$HOME|g" "$SRC/applications/switch-to-niri.desktop" \
  > "$HOME/.local/share/applications/switch-to-niri.desktop"
update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

echo "Installed user files."
echo "Enable the widget with: omarchy plugin enable local.niri-switch --section right"
echo "Restart iNiR shell to pick up the /switch command: systemctl --user restart inir.service"
