#!/usr/bin/env bash
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=wlroots
eval "$(dbus-launch --sh-syntax)" &

# fast launch on GTK/Qt apps
fc-cache -f &
gtk-update-icon-cache -q &

# polkit (auth)
if ! pgrep -x "xfce-polkit" >/dev/null; then
  /usr/lib/xfce-polkit/xfce-polkit &
fi

# Waybar and launcher
awww-daemon &
awww img ~/.config/oxidize/themes/background
waybar &
elephant &
walker --gapplication-service &
