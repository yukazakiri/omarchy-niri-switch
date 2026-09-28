#!/bin/bash
# Install the system files for local.niri-switch. Idempotent — safe to re-run.
#   /usr/local/share/wayland-sessions/omarchy-niri.desktop  (uwsm Niri session)
#   /usr/local/bin/local-niri-switch-set-session             (SDDM target setter)
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
echo "Enable the widget with: omarchy plugin enable local.niri-switch --section right"
