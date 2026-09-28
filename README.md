# Niri Switch (`local.niri-switch`)

Bar widget showing the current compositor (**Hypr** / **Niri**) and the
**boot target**, with buttons to switch between Hyprland and Niri.

## Why it works this way

Omarchy's SDDM setup **autologs in** (`Session=` in
`/etc/sddm.conf.d/autologin.conf`), and the SDDM greeter theme has **no
session-picker UI** (it auto-selects the first "uwsm" session). Worse, SDDM
only autologs at boot — after a logout it shows the greeter, which defaults
back to Hyprland. So switching = rewrite the autologin `Session=` line, then
log out — which is what the switch buttons do (auth via a GUI polkit
dialog).

`Relogin=true` is also set in the autologin conf, so SDDM logs straight back
into the target session after logout (no greeter, no password). Plain
"Log out" therefore also returns you to the current target rather than a
login screen.

## Files

- `manifest.json` — plugin manifest (`bar-widget`, entry `Switcher.qml`)
- `Switcher.qml` — button + popup panel
- `switcher.sh` — `status`, `target`, `set-session`, `switch`, `logout`, …
- `examples/` — copies of the installed system files (reference only)

## System files this relies on (already installed)

- `/usr/local/share/wayland-sessions/omarchy-niri.desktop` — uwsm-managed
  Niri session (`uwsm start -g -1 -e -D Niri niri.desktop`), mirroring the
  stock `omarchy.desktop` (Hyprland).
- `/usr/local/bin/local-niri-switch-set-session` — root helper that only
  rewrites the `Session=` line in the SDDM autologin conf and enforces
  `Relogin=true` (so logout returns straight to the target, bypassing the
  picker-less greeter). Refuses anything except `omarchy.desktop` /
  `omarchy-niri.desktop`.

## Enable

```bash
omarchy plugin validate ~/.config/omarchy/plugins/local.niri-switch
omarchy plugin enable local.niri-switch --section right
omarchy restart shell   # or: omarchy-shell shell rescanPlugins
```

Click the `Hypr` / `Niri` chip in the bar to open the switcher.

## Terminal use (works under Niri too — your iNiR shell replaces the Omarchy bar there)

```bash
~/.config/omarchy/plugins/local.niri-switch/switcher.sh target          # Hyprland / Niri?
~/.config/omarchy/plugins/local.niri-switch/switcher.sh switch niri     # auth, set boot target, log out
~/.config/omarchy/plugins/local.niri-switch/switcher.sh switch hyprland # back to Hyprland
```

## Switching back from Niri (no Omarchy bar there)

`install.sh` also drops these in (user files, no root needed):

- `~/.config/illogical-impulse/actions/switch-to-omarchy` — official iNiR
  GlobalActions user script. Press `Mod+Space`, type **`/switch`** (or
  `/omarchy`), Enter. Auth via GUI polkit dialog, then straight into
  Hyprland. Also runnable headless: `inir globalActions run custom-switch-to-omarchy`.
- `~/.local/share/applications/switch-to-omarchy.desktop` and
  `switch-to-niri.desktop` — plain launcher entries, so typing "switch" in
  any app search (iNiR start menu, Omarchy menu, fuzzel…) finds them.

Restart the iNiR shell after installing to pick up the `/switch` command:
`systemctl --user restart inir.service`.

## Notes

- Omarchy's bar workspaces widget is Hyprland-specific
  (`Quickshell.Hyprland`), so under Niri it would show a static row — but
  your Niri setup runs the iNiR shell instead of the Omarchy bar anyway.
- Your `~/.config/niri/config.kdl` (iNiR) does not spawn
  `omarchy-launch-shell`, which is correct — don't add it or you'll get two
  shells/bars under Niri.

## iNiR autostart under the uwsm session (important)

Stock `niri-session` runs the compositor as the `niri.service` systemd unit,
and iNiR starts via a `niri.service.wants/inir.service` link with
`Requisite=niri.service`. But `omarchy-niri.desktop` runs niri directly
inside `wayland-wm@niri.desktop.service`, so `niri.service` is never active
and iNiR silently never starts (no shell after login).

Three machine-local changes fix it (all under `~/.config/systemd/user/`):

1. Remove `Requisite=niri.service` from `inir.service` (keep `After=` and
   `PartOf=` — stock-flow start/stop behavior is unchanged).
2. `inir.service.d/omarchy-uwsm.conf` drop-in adding
   `PartOf=wayland-wm@niri.desktop.service`, so iNiR stops with the uwsm
   session and never leaks into the next Hyprland login.
3. Wants link `wayland-wm@niri.desktop.service.wants/inir.service`, so iNiR
   starts on Omarchy-Niri login only — never under Hyprland.

Then `systemctl --user daemon-reload` (and `systemctl --user start
inir.service` to fix a live session without logging out).
