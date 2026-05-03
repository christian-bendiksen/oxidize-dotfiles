# oxidize-dotfiles

Wayland desktop dotfiles for AerynOS with an atomic theme switcher
powered by [oxidize](https://github.com/christian-bendiksen/oxidize-theme).
Heavily inspired by Omarchy.

## Requirements

- AerynOS
- `git`, `curl`, `unzip`, `fc-cache` (fontconfig), `envsubst` (gettext)

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/christian-bendiksen/oxidize-dotfiles/main/install-aerynos.sh)
```

Clones to `~/.dotfiles`, symlinks configs into `~/.config`, installs
JetBrains Mono Nerd Font, adw-gtk3 theme, and sets up SDDM. Re-running
the script on an existing install pulls the latest changes and re-applies.

During install you will be asked to pick a window manager:
**niri**, **mango**, or **hypr**.

## Themes

```bash
oxidize set <theme>
```

Available themes: aeryn, catppuccin, catppuccin-latte, ethereal,
everforest, flexoki-light, gruvbox, hackerman, kanagawa, matte-black,
miasma, nord, osaka-jade, ristretto, rose-pine, tokyo-night, vantablack,
white.

Use `oxidize-menu` for an interactive picker, wallpaper selection, and
other system controls.

## User overrides

Any file placed under `~/.dotfiles/user/` mirrors the `~/.config/`
structure and overrides the repo version. Files here are gitignored and
never touched by updates.

Example — custom mango keybinds:

```
~/.dotfiles/user/mango/conf.d/binds.conf
```

Re-run the installer to apply new overrides.

## What's included

**Compositors** — niri, mango, hyprland  
**Bar** — waybar  
**Terminals** — kitty, alacritty  
**Launcher** — walker  
**Editor** — helix  
**Monitor** — btop  
**Notifications** — mako  
**Display manager** — sddm  
