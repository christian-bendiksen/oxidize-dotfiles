#!/usr/bin/env bash
# Wait for awww-daemon to be ready, then set the wallpaper.
SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wayland-1-awww-daemon.sock"
for i in $(seq 1 20); do
    if [[ -S "$SOCKET" ]]; then
        awww img "$HOME/.config/oxidize/themes/background"
        exit 0
    fi
    sleep 0.5
done
echo "start-wallpaper: timed out waiting for awww-daemon" >&2
exit 1
