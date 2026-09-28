#!/bin/bash
# Helper for the local.niri-switch bar widget.
#
# Why this exists: Omarchy's SDDM setup autologs into
# /etc/sddm.conf.d/autologin.conf's Session= (omarchy.desktop = Hyprland),
# and the SDDM greeter theme has no session-picker UI (it auto-selects the
# first "uwsm" session). So "log out to the picker" just loops back to
# Hyprland. Real switching = rewrite the autologin Session= line, then log
# out. The privileged write goes through
# /usr/local/bin/local-niri-switch-set-session via pkexec (GUI, from the
# widget) or sudo (from a terminal).
set -u

cmd="${1:-status}"
SETTER="/usr/local/bin/local-niri-switch-set-session"
AUTOLOGIN_CONF="/etc/sddm.conf.d/autologin.conf"

current_compositor() {
  local desktop="${XDG_CURRENT_DESKTOP:-} ${XDG_SESSION_DESKTOP:-} ${DESKTOP_SESSION:-}"
  case "$desktop" in
    *[Nn]iri*) echo "Niri"; return 0 ;;
    *[Hh]yprland*) echo "Hyprland"; return 0 ;;
  esac
  if pgrep -x niri >/dev/null 2>&1; then echo "Niri"; return 0; fi
  if pgrep -x Hyprland >/dev/null 2>&1; then echo "Hyprland"; return 0; fi
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then echo "Hyprland"; return 0; fi
  if [ -n "${NIRI_SOCKET:-}" ]; then echo "Niri"; return 0; fi
  echo "Unknown"
}

niri_installed() {
  command -v niri >/dev/null 2>&1
}

hypr_installed() {
  command -v Hyprland >/dev/null 2>&1 || command -v hyprctl >/dev/null 2>&1
}

list_sessions() {
  local dirs=(
    "$HOME/.local/share/wayland-sessions"
    "/usr/local/share/wayland-sessions"
    "/usr/share/wayland-sessions"
  )
  local d f
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*.desktop; do
      [ -e "$f" ] || continue
      echo "$f"
    done
  done | sort -u
}

do_logout() {
  # OSD hint (best effort), close windows on Hyprland, then exit
  # the compositor so SDDM autologs into the configured target session.
  (command -v omarchy-osd >/dev/null 2>&1 && omarchy-osd -i logout -m "Logging out" -d 4000) >/dev/null 2>&1 &

  if command -v niri >/dev/null 2>&1 && pgrep -x niri >/dev/null 2>&1; then
    niri msg action quit >/dev/null 2>&1 &
    sleep 1
  fi
  if command -v hyprctl >/dev/null 2>&1 && pgrep -x Hyprland >/dev/null 2>&1; then
    (command -v omarchy-hyprland-window-close-all >/dev/null 2>&1 && omarchy-hyprland-window-close-all >/dev/null 2>&1) || true
    sleep 1
    hyprctl dispatch exit >/dev/null 2>&1 &
    sleep 1
  fi
  # uwsm-managed sessions: stopping returns to the display manager.
  if command -v uwsm >/dev/null 2>&1; then
    nohup bash -c 'sleep 1 && uwsm stop' >/dev/null 2>&1 &
    return 0
  fi
  if command -v omarchy >/dev/null 2>&1; then
    omarchy system logout >/dev/null 2>&1 &
    return 0
  fi
  echo "Could not find a logout method (need uwsm or hyprctl/niri)." >&2
  return 1
}

# Read-only: which compositor will SDDM autolog into next?
boot_target() {
  local session=""
  [ -f "$AUTOLOGIN_CONF" ] && session=$(sed -n 's/^Session=//p' "$AUTOLOGIN_CONF" | head -n 1)
  case "$session" in
    omarchy-niri.desktop) echo "Niri" ;;
    omarchy.desktop) echo "Hyprland" ;;
    "") echo "Unknown (no Session= in $AUTOLOGIN_CONF)" ;;
    *) echo "Unknown ($session)" ;;
  esac
}

elevate() {
  # $1... = command to run as root. Terminal -> sudo, GUI widget -> pkexec.
  if [ -t 0 ] && [ -t 1 ]; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1; then
    pkexec "$@"
  else
    echo "Need root (no terminal for sudo, no pkexec). Run in a terminal:" >&2
    echo "  sudo $*" >&2
    return 1
  fi
}

set_session() {
  local want="${1:-}"
  local desktop=""
  case "$want" in
    hyprland|hypr|omarchy.desktop) desktop="omarchy.desktop" ;;
    niri|omarchy-niri.desktop) desktop="omarchy-niri.desktop" ;;
    *)
      echo "Usage: switcher.sh set-session {hyprland|niri}" >&2
      return 2
      ;;
  esac
  [ -x "$SETTER" ] || {
    echo "Missing $SETTER — reinstall it with:" >&2
    echo "  pkexec cp ~/.config/omarchy/plugins/local.niri-switch/examples/local-niri-switch-set-session /usr/local/bin/ && pkexec chmod 755 /usr/local/bin/local-niri-switch-set-session" >&2
    return 1
  }
  elevate "$SETTER" "$desktop"
}

do_switch() {
  local want="${1:-}"
  case "$want" in
    hyprland|hypr|niri) ;;
    *) echo "Usage: switcher.sh switch {hyprland|niri}" >&2; return 2 ;;
  esac
  set_session "$want" || return $?
  sleep 1
  do_logout
}

case "$cmd" in
  status) current_compositor ;;
  current) current_compositor ;;
  is-niri-installed) niri_installed ;;
  is-hypr-installed) hypr_installed ;;
  sessions) list_sessions ;;
  session-names)
    list_sessions | while IFS= read -r f; do
      name=$(sed -n 's/^Name=//p' "$f" | head -n 1)
      echo "${name:-$(basename "$f")}|$f"
    done
    ;;
  logout) do_logout ;;
  target|boot-target) boot_target ;;
  set-session) set_session "${2:-}" ;;
  switch) do_switch "${2:-}" ;;
  -h|--help|help)
    echo "Usage: switcher.sh {status|target|set-session {hyprland|niri}|switch {hyprland|niri}|sessions|session-names|logout}"
    echo "  status      current compositor (Hyprland/Niri/Unknown)"
    echo "  target      SDDM autologin target (what you boot into next)"
    echo "  switch X    set autologin target to X (auth via sudo/pkexec) and log out"
    ;;
  *) echo "Unknown command: $cmd" >&2; exit 2 ;;
esac
