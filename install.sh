#!/usr/bin/env bash
# install.sh — oxidize-dotfiles installer
#
# Supports: AerynOS, Arch Linux (and Arch-based derivatives)
#
# Usage (fresh machine):
#   git clone https://github.com/christian-bendiksen/oxidize-dotfiles ~/oxidize-dotfiles
#   bash ~/oxidize-dotfiles/install.sh
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/christian-bendiksen/oxidize-dotfiles/main/install.sh | bash
#
# The script is idempotent — safe to re-run.
set -euo pipefail

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
BLU='\033[0;34m'
BLD='\033[1m'
RST='\033[0m'

info()    { printf "${BLU}  ::${RST} %s\n" "$*"; }
ok()      { printf "${GRN}  ok${RST} %s\n" "$*"; }
warn()    { printf "${YLW}warn${RST} %s\n" "$*"; }
die()     { printf "${RED} ERR${RST} %s\n" "$*" >&2; exit 1; }
section() { printf "\n${BLD}==> %s${RST}\n" "$*"; }

DOTFILES_REPO="https://github.com/christian-bendiksen/oxidize-dotfiles"
DOTFILES_DIR="$HOME/oxidize-dotfiles"
OXIDIZE_SRC="$HOME/.local/src/oxidize"
OXIDIZE_BIN="$HOME/.local/bin/oxidize"
OXIDIZE_CURRENT="$HOME/.config/oxidize/themes/current"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# ---------------------------------------------------------------------------
# Distro detection
# ---------------------------------------------------------------------------

detect_distro() {
    [[ -r /etc/os-release ]] || { echo "unknown"; return; }
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
        aerynos) echo "aerynos"; return ;;
        arch|cachyos|endeavouros|manjaro|artix) echo "arch"; return ;;
    esac
    case " ${ID_LIKE:-} " in
        *" arch "*) echo "arch"; return ;;
    esac
    echo "unknown"
}

# ---------------------------------------------------------------------------
# UI helpers (gum when available, plain prompts otherwise)
# ---------------------------------------------------------------------------

ui_confirm() {
    local msg="$1"
    if command -v gum &>/dev/null; then
        gum confirm "$msg"
    else
        local reply
        read -r -p "$msg [y/N] " reply
        [[ "$reply" =~ ^[Yy]$ ]]
    fi
}

# ui_choose_multi <header> <option>...
# Emits selected options on stdout, one per line.
ui_choose_multi() {
    local header="$1"; shift
    if command -v gum &>/dev/null; then
        gum choose --no-limit --header "$header" "$@"
    else
        printf '%s\n' "$header" >&2
        local selected=() opt reply
        for opt in "$@"; do
            read -r -p "  include $opt? [y/N] " reply
            [[ "$reply" =~ ^[Yy]$ ]] && selected+=("$opt")
        done
        [[ ${#selected[@]} -gt 0 ]] && printf '%s\n' "${selected[@]}"
    fi
}

ui_banner() {
    if command -v gum &>/dev/null; then
        gum style --border rounded --border-foreground 212 \
            --padding "0 2" --margin "1 0" \
            "oxidize-dotfiles installer" "detected distro: $DISTRO"
    else
        printf "\n${BLD}oxidize-dotfiles installer${RST}\n"
        printf "detected distro: ${BLD}%s${RST}\n\n" "$DISTRO"
    fi
}

# ---------------------------------------------------------------------------
# Package-manager abstraction
# ---------------------------------------------------------------------------

pm_install() {
    [[ $# -eq 0 ]] && return 0
    case "$DISTRO" in
        aerynos) sudo moss install -y "$@" ;;
        arch)    sudo pacman -S --needed --noconfirm "$@" ;;
        *)       die "No package-manager support for distro: $DISTRO" ;;
    esac
}

aur_install() {
    [[ $# -eq 0 ]] && return 0
    paru -S --needed --noconfirm "$@"
}

# ---------------------------------------------------------------------------
# Distro-specific setup
# ---------------------------------------------------------------------------

setup_aerynos_repos() {
    sudo moss repo add volatile https://build.aerynos.dev/stream/volatile/x86_64/stone.index -p 10 || true
    sudo moss repo enable volatile
    sudo moss sync -u -y
    ok "Volatile repo enabled"
}

setup_paru() {
    if command -v paru &>/dev/null; then
        ok "found paru ($(command -v paru))"
        return
    fi
    warn "'paru' not found — bootstrapping from AUR..."
    sudo pacman -S --needed --noconfirm base-devel git
    local build_dir
    build_dir="$(mktemp -d)"
    git clone https://aur.archlinux.org/paru-bin.git "$build_dir/paru-bin"
    (cd "$build_dir/paru-bin" && makepkg -si --noconfirm)
    rm -rf "$build_dir"
    ok "paru installed"
}

bootstrap_gum() {
    if command -v gum &>/dev/null; then
        ok "found gum ($(command -v gum))"
        return
    fi
    info "Installing gum for interactive prompts..."
    if pm_install gum; then
        ok "gum installed"
    else
        warn "gum not installable via package manager — falling back to plain prompts"
    fi
}

# ---------------------------------------------------------------------------
# Package maps
# ---------------------------------------------------------------------------

base_packages() {
    case "$DISTRO" in
        aerynos)
            printf '%s\n' \
                alacritty awww btop build-essential cava curl \
                gpu-screen-recorder grim slurp helix \
                power-profiles-daemon walker waybar yaru-icon-theme \
                nautilus xdg-utils brightnessctl iwd playerctl \
                pavucontrol impala bluetui swaylock elephant swayidle
            ;;
        arch)
            printf '%s\n' \
                alacritty btop cava curl git grim slurp helix \
                power-profiles-daemon waybar mako \
                nautilus xdg-utils brightnessctl iwd playerctl \
                pavucontrol swaylock swayidle unzip base-devel
            ;;
    esac
}

base_aur_packages() {
    case "$DISTRO" in
        arch) printf '%s\n' yaru-icon-theme-git walker elephant-all awww impala bluetui gpu-screen-recorder ;;
    esac
}

wm_packages() {
    local wm="$1"
    case "$DISTRO:$wm" in
        aerynos:niri)   printf '%s\n' niri ;;
        aerynos:mango)  ;;  # mango not yet in AerynOS repos
        arch:niri)      printf '%s\n' niri ;;
        arch:hyprland)  printf '%s\n' hyprland hyprpaper hypridle hyprlock xdg-desktop-portal-hyprland ;;
        arch:mango)     ;;  # via AUR (see wm_aur_packages)
    esac
}

wm_aur_packages() {
    local wm="$1"
    case "$DISTRO:$wm" in
        arch:mango) printf '%s\n' mango ;;
    esac
}

available_wms() {
    case "$DISTRO" in
        aerynos) printf '%s\n' niri mango ;;
        arch)    printf '%s\n' niri mango hyprland ;;
    esac
}

# ---------------------------------------------------------------------------
# Symlink helper
# ---------------------------------------------------------------------------

# safe_pull <repo-dir>
# Fast-forwards the repo if the working tree is clean. Otherwise warns and
# leaves it alone so local edits (work-in-progress templates, etc.) aren't lost.
safe_pull() {
    local dir="$1"
    if ! git -C "$dir" diff --quiet || ! git -C "$dir" diff --cached --quiet; then
        warn "Local changes in $dir — skipping pull"
        return 0
    fi
    if git -C "$dir" pull --ff-only; then
        ok "Updated $dir"
    else
        warn "git pull failed in $dir — continuing with current state"
    fi
}

link() {
    local src="$1" dst="$2"
    [[ -z "$src" || -z "$dst" ]] && die "link(): empty src or dst (src='$src' dst='$dst')"
    # Strip trailing slashes so a stray '/' can't widen the target.
    dst="${dst%/}"
    src="${src%/}"
    case "$dst" in
        "" | "/" | "$HOME" | "$HOME/.config")
            die "link(): refusing to touch protected path '$dst'"
            ;;
    esac
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        ok "(already linked) $dst"
        return
    fi
    if [[ -e "$dst" || -L "$dst" ]]; then
        local bak="${dst}.bak.${TIMESTAMP}"
        warn "Backing up existing '$dst' -> '$bak'"
        mv "$dst" "$bak"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    ok "$dst -> $src"
}

# ---------------------------------------------------------------------------
# Begin
# ---------------------------------------------------------------------------

[[ "$EUID" -eq 0 ]] && die "Do not run as root."

DISTRO="$(detect_distro)"
case "$DISTRO" in
    aerynos|arch) ;;
    *) die "Unsupported distro (detected: ${DISTRO}). Supported: AerynOS, Arch-based." ;;
esac

ui_banner

printf "This will install system packages, build the oxidize binary,\n"
printf "and symlink dotfiles into ~/.config.\n\n"

if ! ui_confirm "Proceed with installation?"; then
    printf "Aborted.\n"
    exit 0
fi

section "Pre-flight checks"

if ! command -v git &>/dev/null; then
    info "Installing git..."
    pm_install git
fi
ok "found git ($(command -v git))"

# AerynOS volatile repo must be enabled before gum / base installs.
if [[ "$DISTRO" == "aerynos" ]]; then
    section "Setting up volatile repo"
    setup_aerynos_repos
fi

section "Bootstrapping gum"
bootstrap_gum

section "Choosing window managers"
mapfile -t WM_OPTIONS < <(available_wms)
mapfile -t _raw_wms < <(ui_choose_multi "Select window manager(s) to install:" "${WM_OPTIONS[@]}")
SELECTED_WMS=()
for _wm in "${_raw_wms[@]}"; do
    [[ -n "$_wm" ]] && SELECTED_WMS+=("$_wm")
done
unset _raw_wms _wm
[[ ${#SELECTED_WMS[@]} -eq 0 ]] && die "At least one window manager must be selected."
ok "Selected: ${SELECTED_WMS[*]}"

# ---------------------------------------------------------------------------
# Package installation
# ---------------------------------------------------------------------------

PACMAN_OR_MOSS_PKGS=()
while IFS= read -r pkg; do [[ -n "$pkg" ]] && PACMAN_OR_MOSS_PKGS+=("$pkg"); done < <(base_packages)

AUR_PKGS=()
if [[ "$DISTRO" == "arch" ]]; then
    while IFS= read -r pkg; do [[ -n "$pkg" ]] && AUR_PKGS+=("$pkg"); done < <(base_aur_packages)
fi

for wm in "${SELECTED_WMS[@]}"; do
    pre=${#PACMAN_OR_MOSS_PKGS[@]}
    aur_pre=${#AUR_PKGS[@]}
    while IFS= read -r pkg; do [[ -n "$pkg" ]] && PACMAN_OR_MOSS_PKGS+=("$pkg"); done < <(wm_packages "$wm")
    if [[ "$DISTRO" == "arch" ]]; then
        while IFS= read -r pkg; do [[ -n "$pkg" ]] && AUR_PKGS+=("$pkg"); done < <(wm_aur_packages "$wm")
    fi
    if [[ ${#PACMAN_OR_MOSS_PKGS[@]} -eq $pre && ${#AUR_PKGS[@]} -eq $aur_pre ]]; then
        warn "$wm has no packaged build on $DISTRO — you'll need to install it manually"
    fi
done

section "Installing base dependencies"
info "Packages: ${PACMAN_OR_MOSS_PKGS[*]}"
pm_install "${PACMAN_OR_MOSS_PKGS[@]}"
ok "Base dependencies installed"

if [[ "$DISTRO" == "arch" ]]; then
    section "Setting up AUR helper (paru)"
    setup_paru
    if [[ ${#AUR_PKGS[@]} -gt 0 ]]; then
        section "Installing AUR dependencies"
        info "Packages: ${AUR_PKGS[*]}"
        aur_install "${AUR_PKGS[@]}"
        ok "AUR dependencies installed"
    fi
fi

# ---------------------------------------------------------------------------
# Rust / cargo
# ---------------------------------------------------------------------------

if ! command -v cargo &>/dev/null; then
    warn "'cargo' not found — installing rustup..."
    case "$DISTRO" in
        arch)
            sudo pacman -S --needed --noconfirm rustup
            rustup default stable
            ;;
        aerynos)
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y
            # shellcheck source=/dev/null
            source "$HOME/.cargo/env"
            ;;
    esac
    if ! command -v cargo &>/dev/null; then
        die "rustup installed but 'cargo' still not found. Open a new shell and retry."
    fi
fi
ok "found cargo ($(command -v cargo))"

# ---------------------------------------------------------------------------
# Fonts & GTK theme
# ---------------------------------------------------------------------------

section "Installing JetBrains Mono Nerd Font"

FONT_DIR="$HOME/.local/share/fonts/JetbrainsMono"
if [[ -d "$FONT_DIR" ]]; then
    ok "JetBrains Mono Nerd Font already installed"
else
    mkdir -p "$FONT_DIR"
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip" \
        -o /tmp/JetBrainsMono.zip
    unzip -q /tmp/JetBrainsMono.zip -d "$FONT_DIR"
    rm /tmp/JetBrainsMono.zip
    fc-cache -f
    ok "JetBrains Mono Nerd Font installed -> $FONT_DIR"
fi

section "Installing adw-gtk3 theme"

ADW_DIR="$HOME/.local/share/themes"
if ls "$ADW_DIR"/adw-gtk3* &>/dev/null; then
    ok "adw-gtk3 theme already installed"
else
    mkdir -p "$ADW_DIR"
    curl -fsSL "https://github.com/lassekongo83/adw-gtk3/releases/download/v6.4/adw-gtk3v6.4.tar.xz" \
        -o /tmp/adw-gtk3.tar.xz
    tar -xf /tmp/adw-gtk3.tar.xz -C "$ADW_DIR"
    rm /tmp/adw-gtk3.tar.xz
    ok "adw-gtk3 theme installed -> $ADW_DIR"
fi

mkdir -p "$HOME/.local/bin"

# ---------------------------------------------------------------------------
# Dotfiles & oxidize
# ---------------------------------------------------------------------------

section "Cloning oxidize-dotfiles"

if [[ -d "$DOTFILES_DIR/.git" ]]; then
    info "Updating existing clone..."
    safe_pull "$DOTFILES_DIR"
else
    if [[ -e "$DOTFILES_DIR" ]]; then
        warn "Backing up existing '$DOTFILES_DIR'"
        mv "$DOTFILES_DIR" "${DOTFILES_DIR}.bak.${TIMESTAMP}"
    fi
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi
ok "oxidize-dotfiles ready at $DOTFILES_DIR"

section "Building oxidize"

if [[ -d "$OXIDIZE_SRC/.git" ]]; then
    info "Updating existing oxidize-theme clone..."
    safe_pull "$OXIDIZE_SRC"
else
    info "Cloning oxidize-theme..."
    mkdir -p "$(dirname "$OXIDIZE_SRC")"
    git clone https://github.com/christian-bendiksen/oxidize "$OXIDIZE_SRC"
fi

info "Running cargo build --release (this may take a minute)..."
cargo build --release --manifest-path "$OXIDIZE_SRC/Cargo.toml"

cp "$OXIDIZE_SRC/target/release/oxidize" "$OXIDIZE_BIN"
ok "Installed oxidize binary -> $OXIDIZE_BIN"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

BASHRC="$HOME/.bashrc"
touch "$BASHRC"
if ! grep -qF 'local/bin' "$BASHRC"; then
    printf '\n# Added by oxidize install.sh\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$BASHRC"
    ok "Added ~/.local/bin to PATH in $BASHRC"
else
    ok "~/.local/bin already in PATH"
fi

section "Setting up bash aliases"

ALIASES_SNIPPET="# oxidize-dotfiles aliases
if [ -f \"$DOTFILES_DIR/bashrc/aliases.sh\" ]; then
    source \"$DOTFILES_DIR/bashrc/aliases.sh\"
fi"

if grep -qF "oxidize-dotfiles aliases" "$BASHRC"; then
    ok "Aliases already sourced in $BASHRC"
else
    printf '\n%s\n' "$ALIASES_SNIPPET" >> "$BASHRC"
    ok "Added aliases source to $BASHRC"
fi

# ---------------------------------------------------------------------------
# Symlinks
# ---------------------------------------------------------------------------

section "Linking helper scripts"

link "$DOTFILES_DIR/bin/oxidize-sysctl"    "$HOME/.local/bin/oxidize-sysctl"
link "$DOTFILES_DIR/bin/xdg-terminal-exec" "$HOME/.local/bin/xdg-terminal-exec"

section "Setting up oxidize theme directories"

link "$DOTFILES_DIR/oxidize/themes/data"      "$HOME/.config/oxidize/themes/data"
link "$DOTFILES_DIR/oxidize/themes/templates" "$HOME/.config/oxidize/themes/templates"
oxidize init

section "Linking common config directories"

COMMON_CONFIGS=(
    kitty alacritty waybar mako btop helix fuzzel walker
    gtk-3.0 gtk-4.0 fontconfig
)
for cfg in "${COMMON_CONFIGS[@]}"; do
    src="$DOTFILES_DIR/$cfg"
    if [[ -e "$src" ]]; then
        link "$src" "$HOME/.config/$cfg"
    else
        warn "$cfg not present in repo — skipping"
    fi
done

link "$DOTFILES_DIR/starship.toml"       "$HOME/.config/starship.toml"
link "$DOTFILES_DIR/chromium-flags.conf" "$HOME/.config/chromium-flags.conf"
link "$DOTFILES_DIR/bashrc"              "$HOME/.config/bashrc"

section "Linking selected window-manager configs"

for wm in "${SELECTED_WMS[@]}"; do
    src="$DOTFILES_DIR/$wm"
    if [[ -e "$src" ]]; then
        link "$src" "$HOME/.config/$wm"
    else
        warn "$wm config not yet present in repo — skipping symlink"
    fi
done

section "Wiring per-file oxidize theme symlinks"

link "$OXIDIZE_CURRENT/gtk.css"          "$HOME/.config/gtk-3.0/gtk.css"
link "$OXIDIZE_CURRENT/gtk.css"          "$HOME/.config/gtk-4.0/gtk.css"
link "$OXIDIZE_CURRENT/mako.ini"         "$HOME/.config/mako/config"

if [[ " ${SELECTED_WMS[*]} " == *" niri "* && -e "$DOTFILES_DIR/niri" ]]; then
    link "$OXIDIZE_CURRENT/niri-colors.kdl"  "$HOME/.config/niri/niri-colors.kdl"
fi

link "$OXIDIZE_CURRENT/btop.theme"       "$HOME/.config/btop/themes/current.theme"
link "$OXIDIZE_CURRENT/helix.toml"       "$HOME/.config/helix/themes/oxidize.toml"

section "Setting defaults"
oxidize set aeryn

section "Done"
printf "Next step:\n"
printf "  ${BLD}oxidize set <theme-name>${RST}   — apply your first theme\n"
printf "Available themes in: $DOTFILES_DIR/oxidize/themes/data/\n\n"

if ui_confirm "Reboot now?"; then
    sudo reboot
fi
