#!/usr/bin/env bash
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/christian-bendiksen/oxidize-dotfiles/main/install-aerynos.sh)
set -euo pipefail

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
BLU='\033[0;34m'
BLD='\033[1m'
DIM='\033[2m'
RST='\033[0m'

ok()   { printf "  ${GRN}✓${RST}  %s\n"       "$*"; }
warn() { printf "  ${YLW}!${RST}  %s\n"        "$*"; }
die()  { printf "  ${RED}✗${RST}  %s\n" "$*" >&2; exit 1; }

section() {
    local label=" $* " width=44
    local line; printf -v line '%*s' "$width" ''; line="${line// /─}"
    printf "\n${BLU}${BLD}%s${RST}${DIM}%s${RST}\n" \
        "$label" "${line:${#label}}"
}

banner() {
    printf "\n"
    printf "  ${BLD}╭──────────────────────────────────────╮${RST}\n"
    printf "  ${BLD}│${RST}   oxidize-dotfiles  ·  AerynOS       ${BLD}│${RST}\n"
    printf "  ${BLD}╰──────────────────────────────────────╯${RST}\n"
    printf "\n"
}

confirm() {
    local reply
    read -r -p "  $* [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

pick() {
    local label="$1"; shift
    local opts=("$@") i reply
    printf "  %s\n" "$label" >&2
    for i in "${!opts[@]}"; do
        printf "    ${BLD}%d)${RST} %s\n" "$((i+1))" "${opts[$i]}" >&2
    done
    while true; do
        read -r -p "  Choice [1-${#opts[@]}]: " reply
        if [[ "$reply" =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= ${#opts[@]} )); then
            printf '%s' "${opts[$((reply-1))]}"; return
        fi
        warn "Enter a number between 1 and ${#opts[@]}" >&2
    done
}

spin() {
    local pid="$1" msg="$2"
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${BLU}${frames[$((i++ % 10))]}${RST}  %s" "$msg"
        sleep 0.08
    done
    printf "\r%*s\r" "$((${#msg} + 6))" ""  # clear the line
}

DOTFILES_REPO="https://github.com/christian-bendiksen/oxidize-dotfiles"
DOTFILES_DIR="$HOME/.dotfiles"
OXIDIZE_CURRENT="$HOME/.config/oxidize/themes/current"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

link() {
    local src="$1" dst="$2"
    [[ -z "$src" || -z "$dst" ]] && die "link(): empty src or dst"
    dst="${dst%/}"; src="${src%/}"
    case "$dst" in
        "" | "/" | "$HOME" | "$HOME/.config")
            die "link(): refusing to touch protected path '$dst'"
            ;;
    esac
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        ok "(already linked) ${dst/$HOME/\~}"
        return
    fi
    if [[ -e "$dst" || -L "$dst" ]]; then
        warn "Backing up ${dst/$HOME/\~}"
        mv "$dst" "${dst}.bak.${TIMESTAMP}"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    ok "${dst/$HOME/\~} → ${src/$HOME/\~}"
}

safe_pull() {
    local dir="$1"

    if ! git -C "$dir" diff --quiet || ! git -C "$dir" diff --cached --quiet; then
        warn "Local changes detected — stashing before update"
        git -C "$dir" stash push -m "oxidize-installer-backup-${TIMESTAMP}" --quiet
        ok "Changes stashed (recover with: git -C ${dir/$HOME/\~} stash pop)"
    fi

    git -C "$dir" fetch --quiet

    # Remove only untracked files that now exist on origin/main
    git -C "$dir" ls-files --others --exclude-standard -z |
    while IFS= read -r -d '' f; do
        if git -C "$dir" cat-file -e "origin/main:$f" 2>/dev/null; then
            warn "Removing untracked file that would block merge: $f"
            rm -f -- "$dir/$f"
        fi
    done

    git -C "$dir" merge --ff-only --quiet origin/main \
        && ok "Updated ${dir/$HOME/\~}" \
        || warn "git pull failed — continuing with current state"
}

banner

[[ "$EUID" -eq 0 ]] && die "Do not run as root."
command -v git &>/dev/null || die "'git' not found — install it first."

IS_UPDATE=false
if [[ -d "$DOTFILES_DIR/.git" ]]; then
    IS_UPDATE=true
    printf "  Existing installation detected — pulling latest changes\n"
    printf "  and re-applying configs.\n\n"
else
    printf "  This will clone the dotfiles to ${BLD}~/.dotfiles${RST} and\n"
    printf "  symlink configs into ${BLD}~/.config${RST}.\n\n"
fi

confirm "Proceed?" || { printf "\n  Aborted.\n\n"; exit 0; }

section "Dotfiles"

if $IS_UPDATE; then
    safe_pull "$DOTFILES_DIR"
else
    if [[ -e "$DOTFILES_DIR" ]]; then
        warn "Backing up existing ~/.dotfiles"
        mv "$DOTFILES_DIR" "${DOTFILES_DIR}.bak.${TIMESTAMP}"
    fi
    git clone --quiet "$DOTFILES_REPO" "$DOTFILES_DIR" &
    spin $! "Cloning oxidize-dotfiles…"
    wait $!
    ok "Cloned to ~/.dotfiles"
fi

if ! $IS_UPDATE; then
    section "Window manager"

    CHOSEN_WM=$(pick "Which window manager would you like to install?" niri mango hypr)
    ok "Selected: $CHOSEN_WM"

    PKGSET="pkgset-oxidize-${CHOSEN_WM}"
    printf "  Installing ${BLD}%s${RST}…\n" "$PKGSET"
    sudo moss install "$PKGSET" && ok "Installed $PKGSET" \
        || warn "Failed to install $PKGSET — continuing anyway"
fi

section "JetBrains Mono Nerd Font"

FONT_DIR="$HOME/.local/share/fonts/JetbrainsMono"
if [[ -d "$FONT_DIR" ]]; then
    ok "Already installed"
else
    mkdir -p "$FONT_DIR"
    {
        curl -fsSL \
            "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip" \
            -o /tmp/JetBrainsMono.zip
        unzip -q /tmp/JetBrainsMono.zip -d "$FONT_DIR"
        rm /tmp/JetBrainsMono.zip
        fc-cache -f
    } &
    spin $! "Downloading & installing font…"
    wait $!
    ok "Installed → ~/.local/share/fonts/JetbrainsMono"
fi

section "adw-gtk3 theme"

ADW_DIR="$HOME/.local/share/themes"
if ls "$ADW_DIR"/adw-gtk3* &>/dev/null 2>&1; then
    ok "Already installed"
else
    mkdir -p "$ADW_DIR"
    {
        curl -fsSL \
            "https://github.com/lassekongo83/adw-gtk3/releases/download/v6.4/adw-gtk3v6.4.tar.xz" \
            -o /tmp/adw-gtk3.tar.xz
        tar -xf /tmp/adw-gtk3.tar.xz -C "$ADW_DIR"
        rm /tmp/adw-gtk3.tar.xz
    } &
    spin $! "Downloading & extracting theme…"
    wait $!
    ok "Installed → ~/.local/share/themes"
fi

section "Oxidize theme directories"

link "$DOTFILES_DIR/oxidize/themes/data"      "$HOME/.config/oxidize/themes/data"
link "$DOTFILES_DIR/oxidize/themes/templates" "$HOME/.config/oxidize/themes/templates"
oxidize init

section "Common config directories"

COMMON_CONFIGS=(
    kitty alacritty waybar mako btop helix walker
    gtk-3.0 gtk-4.0 fontconfig swayosd sddm
)
for cfg in "${COMMON_CONFIGS[@]}"; do
    src="$DOTFILES_DIR/$cfg"
    if [[ -e "$src" ]]; then
        link "$src" "$HOME/.config/$cfg"
    else
        warn "$cfg not in repo — skipping"
    fi
done

link "$DOTFILES_DIR/chromium-flags.conf" "$HOME/.config/chromium-flags.conf"
link "$DOTFILES_DIR/bashrc"              "$HOME/.config/bashrc"

section "Window-manager configs"

for wm in niri mango hypr; do
    src="$DOTFILES_DIR/$wm"
    if [[ -e "$src" ]]; then
        link "$src" "$HOME/.config/$wm"
    fi
done

section "Systemd services"

systemctl --user mask --now waybar.service \
    && ok "waybar.service masked (managed by oxidize-services)" \
    || warn "Failed to mask waybar.service"

section "Oxidize theme wiring"

link "$OXIDIZE_CURRENT/gtk.css"         "$HOME/.config/gtk-3.0/gtk.css"
link "$OXIDIZE_CURRENT/gtk.css"         "$HOME/.config/gtk-4.0/gtk.css"
link "$OXIDIZE_CURRENT/mako.ini"        "$HOME/.config/mako/config"
link "$OXIDIZE_CURRENT/btop.theme"      "$HOME/.config/btop/themes/current.theme"
link "$OXIDIZE_CURRENT/helix.toml"      "$HOME/.config/helix/themes/oxidize.toml"
link "$OXIDIZE_CURRENT/sddm-theme.conf" "$HOME/.config/sddm/themes/oxidize/theme.conf"
link "$HOME/.config/oxidize/themes/background" "$HOME/.config/sddm/themes/oxidize/background"

if [[ -e "$DOTFILES_DIR/niri" ]]; then
    link "$OXIDIZE_CURRENT/niri-colors.kdl" "$HOME/.config/niri/niri-colors.kdl"
fi

section "Shell config"

PROFILE="$HOME/.profile"
touch "$PROFILE"
PROFILE_SNIPPET="# oxidize-dotfiles
export PATH=\"\$HOME/.dotfiles/bin:\$PATH\""
if grep -qF "oxidize-dotfiles" "$PROFILE"; then
    ok "Profile: already configured"
else
    printf '\n%s\n' "$PROFILE_SNIPPET" >> "$PROFILE"
    ok "Profile: added PATH to .profile"
fi

DOTFILES_BASHRC_SNIPPET="# oxidize-dotfiles bashrc
if [ -f \"$DOTFILES_DIR/bashrc/bashrc.sh\" ]; then
    source \"$DOTFILES_DIR/bashrc/bashrc.sh\"
fi"
BASHRC="$HOME/.bashrc"
touch "$BASHRC"
if grep -qF "oxidize-dotfiles bashrc" "$BASHRC"; then
    ok "Bash: already configured"
else
    printf '\n%s\n' "$DOTFILES_BASHRC_SNIPPET" >> "$BASHRC"
    ok "Bash: added dotfiles source to .bashrc"
fi

ZSHRC="$HOME/.zshrc"
if [[ -f "$ZSHRC" ]] || command -v zsh &>/dev/null; then
    touch "$ZSHRC"
    ZSHRC_SNIPPET="# oxidize-dotfiles
if [ -f \"$DOTFILES_DIR/bashrc/bashrc.sh\" ]; then
    source \"$DOTFILES_DIR/bashrc/bashrc.sh\"
fi"
    if grep -qF "oxidize-dotfiles" "$ZSHRC"; then
        ok "Zsh: already configured"
    else
        printf '\n%s\n' "$ZSHRC_SNIPPET" >> "$ZSHRC"
        ok "Zsh: added dotfiles source to .zshrc"
    fi
fi

if command -v fish &>/dev/null; then
    FISH_CONF_DIR="$HOME/.config/fish/conf.d"
    FISH_PATH_FILE="$FISH_CONF_DIR/oxidize-path.fish"
    mkdir -p "$FISH_CONF_DIR"
    if [[ -f "$FISH_PATH_FILE" ]]; then
        ok "Fish: already configured"
    else
        printf 'fish_add_path %s/.dotfiles/bin\n' "$HOME" > "$FISH_PATH_FILE"
        ok "Fish: added PATH to conf.d/oxidize-path.fish"
    fi
fi

section "Display manager (SDDM)"

if command -v sddm &>/dev/null; then
    sudo mkdir -p /etc/sddm.conf.d
    sed "s|HOME|$HOME|g" "$DOTFILES_DIR/sddm/sddm.conf.d/oxidize.conf" \
        | sudo tee /etc/sddm.conf.d/oxidize.conf > /dev/null
    ok "SDDM configured (ThemeDir: ~/.config/sddm/themes)"
    sudo systemctl enable sddm
    ok "sddm enabled"
else
    warn "sddm not found — skipping display manager setup"
fi

section "Applying default theme"

oxidize set aeryn
ok "Theme set to aeryn"

printf "\n  ${GRN}${BLD}Setup complete.${RST}\n"
printf "  Run ${BLD}oxidize set <theme>${RST} to switch themes.\n"
printf "  Themes: ${DIM}~/.dotfiles/oxidize/themes/data/${RST}\n\n"

confirm "Reboot now?" && sudo reboot
printf "\n"
