#!/usr/bin/env bash
# install.sh — oxidize-dotfiles installer for AerynOS
#
# Usage (fresh machine):
#   git clone https://github.com/christian-bendiksen/oxidize-dotfiles ~/oxidize-dotfiles
#   bash ~/oxidize-dotfiles/install.sh
#
# The script is also safe to re-run (idempotent).
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

# Paths 
DOTFILES_REPO="https://github.com/christian-bendiksen/oxidize-dotfiles"
DOTFILES_DIR="$HOME/oxidize-dotfiles"
OXIDIZE_SRC="$HOME/.local/src/oxidize-theme"
OXIDIZE_BIN="$HOME/.local/bin/oxidize"
OXIDIZE_CURRENT="$HOME/.config/oxidize/themes/current"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# Run
printf "\n${BLD}oxidize-dotfiles installer${RST}\n"
printf "This will install system packages, build the oxidize binary,\n"
printf "and symlink dotfiles into ~/.config.\n\n"
read -r -p "Proceed with installation? [y/N] " _reply
[[ "$_reply" =~ ^[Yy]$ ]] || { printf "Aborted.\n"; exit 0; }

# Pre-flight
section "Pre-flight checks"

[[ "$EUID" -eq 0 ]] && die "Do not run as root."

# check for git
if ! command -v git &>/dev/null; then
    die "'git' not found. Install it before running this script."
fi
ok "found git ($(command -v git))"

# Set up volatile and Install system dependencies
section "Setting up volatile repo"

sudo moss repo add volatile https://build.aerynos.dev/stream/volatile/x86_64/stone.index -p 10
sudo moss repo enable volatile
sudo moss sync -u -y
ok "Volatile enabled"

section "Installing dependencies via moss"

PACKAGES=(
    alacritty awww btop build-essential cava curl
    gpu-screen-recorder grim slurp helix niri
    power-profiles-daemon walker waybar yaru-icon-theme
    nautilus xdg-utils brightnessctl iwd
)

info "Running: sudo moss install -u ${PACKAGES[*]}"
sudo moss install -y "${PACKAGES[@]}"
ok "Dependencies installed"

# check for cargo
if ! command -v cargo &>/dev/null; then
    warn "'cargo' not found - installing rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y

    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
    if ! command -v cargo &>/dev/null; then
        die "rustup installed but 'cargo' still not found. Open a new shell and retry."
    fi
fi
ok "found cargo ($(command -v cargo))"

# Install Jetbrains Mono Nerd font
section "Installing Jetbrains Mono Nerd Font"

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

# Install adw-gtk3 theme
section "Installing adw-gtk3 theme"

ADW_DIR="$HOME/.local/share/themes"
if ls "$ADW_DIR"/adw-gtk3* &>/dev/null 2>&1; then
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

# Clone and setup oxidize-dotfiles
# Resolve the current script directory
# and move dotfiles to always live at ~/oxidize-dotfiles
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}:-")" 2>/dev/null && pwd || true)"

if [[ -z "$SCRIPT_DIR" ]]; then
    # Running via curl pipe — no local repo, clone fresh
    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        info "Updating existing oxidize-dotfiles clone at $DOTFILES_DIR..."
        git -C "$DOTFILES_DIR" pull --ff-only
    else
        if [[ -e "$DOTFILES_DIR" ]]; then
            bak="${DOTFILES_DIR}.bak.${TIMESTAMP}"
            warn "Backing up existing '$DOTFILES_DIR' -> '$bak'"
            mv "$DOTFILES_DIR" "$bak"
        fi
        info "Cloning oxidize-dotfiles -> $DOTFILES_DIR"
        git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
    fi
elif [[ "$SCRIPT_DIR" == "$DOTFILES_DIR" ]]; then
    # already in the correct location - just pull
    info "Updating existing oxidize-dotfiles clone..."
    git -C "$DOTFILES_DIR" pull --ff-only
elif [[ -d "$DOTFILES_DIR/.git" ]]; then
    info "Updating existing oxidize-dotfiles clone at $DOTFILES_DIR..."
    git -C "$DOTFILES_DIR" pull --ff-only
else
    # Script is running from another directory - move the repo
    if [[ -e "$DOTFILES_DIR" ]]; then
        bak="${DOTFILES_DIR}.bak.${TIMESTAMP}"
        warn "Backing up existing '$DOTFILES_DIR' -> '$bak'"
        mv "$DOTFILES_DIR" "$bak"
    fi
    info "Moving repo from $SCRIPT_DIR -> $DOTFILES_DIR"
    mv "$SCRIPT_DIR" "$DOTFILES_DIR"
fi
ok "oxidize-dotfiles ready at $DOTFILES_DIR"

# Helper: safe symlink
# link <source> <destination>
# - Skips if destination already points to source (idempotent).
# - Backs up any existing file/dir that is not already the correct symlink.
link() {
    local src="$1"
    local dst="$2"

    # Already correct — nothing to do
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        ok "(already linked) $dst"
        return
    fi

    # Something else exists — back it up
    if [[ -e "$dst" || -L "$dst" ]]; then
        local bak="${dst}.bak.${TIMESTAMP}"
        warn "Backing up existing '$dst' -> '$bak'"
        mv "$dst" "$bak"
    fi

    # Ensure parent directory exists
    mkdir -p "$(dirname "$dst")"

    ln -s "$src" "$dst"
    ok "$dst -> $src"
}

# Build & install oxidize binary
section "Building oxidize"

if [[ -d "$OXIDIZE_SRC/.git" ]]; then
    info "Updating existing oxidize-theme clone..."
    git -C "$OXIDIZE_SRC" pull --ff-only
else
    info "Cloning oxidize-theme..."
    mkdir -p "$(dirname "$OXIDIZE_SRC")"
    git clone https://github.com/christian-bendiksen/oxidize-theme "$OXIDIZE_SRC"
fi

info "Running cargo build --release (this may take a minute)..."
cargo build --release --manifest-path "$OXIDIZE_SRC/Cargo.toml"

cp "$OXIDIZE_SRC/target/release/oxidize" "$OXIDIZE_BIN"
ok "Installed oxidize binary -> $OXIDIZE_BIN"

# Ensure ~/.local/bin is on PATH in ~/.bashrc
BASHRC="$HOME/.bashrc"
touch "$BASHRC"
if ! grep -qF 'local/bin' "$BASHRC"; then
    printf '\n# Added by oxidize install.sh\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$BASHRC"
    ok "Added ~/.local/bin to PATH in $BASHRC"
else
    ok "~/.local/bin already in PATH"
fi

# Bash aliases
section "Setting up bash aliases"

touch "$BASHRC"
ALIASES_SNIPPET="# oxidize-dotfiles aliases
if [ -f \"$DOTFILES_DIR/bashrc/aliases.sh\" ]; then
    source \"$DOTFILES_DIR/bashrc/aliases.sh\"
fi"

if grep -qF "oxidize-dotfiles aliases" "$BASHRC"; then
    ok "Aliases already sourced in $BASHRC"
else
    printf '\n%s\n' "$ALIASES_SNIPPET" >> "$BASHRC"
    ok "Added aliases source to $BASHRC"
    # shellcheck source=/dev/null
    source "$HOME/.bashrc"
fi

# Oxidize theme directory structure
section "Setting up oxidize theme directories"

# The live dir must exist as a real directory so oxidize can populate it
mkdir -p "$HOME/.config/oxidize/themes/generated/live"
ok "Created ~/.config/oxidize/themes/generated/live"

# Link theme data and templates from the dotfiles repo
link "$DOTFILES_DIR/oxidize/themes/data"      "$HOME/.config/oxidize/themes/data"
link "$DOTFILES_DIR/oxidize/themes/templates" "$HOME/.config/oxidize/themes/templates"

# Whole-directory dotfile symlinks
section "Linking dotfile config directories"

link "$DOTFILES_DIR/kitty"              "$HOME/.config/kitty"
link "$DOTFILES_DIR/alacritty"          "$HOME/.config/alacritty"
link "$DOTFILES_DIR/waybar"             "$HOME/.config/waybar"
link "$DOTFILES_DIR/niri"               "$HOME/.config/niri"
link "$DOTFILES_DIR/mango"              "$HOME/.config/mango"
link "$DOTFILES_DIR/mako"               "$HOME/.config/mako"
link "$DOTFILES_DIR/btop"               "$HOME/.config/btop"
link "$DOTFILES_DIR/helix"              "$HOME/.config/helix"
link "$DOTFILES_DIR/fuzzel"             "$HOME/.config/fuzzel"
link "$DOTFILES_DIR/walker"             "$HOME/.config/walker"
link "$DOTFILES_DIR/gtk-3.0"            "$HOME/.config/gtk-3.0"
link "$DOTFILES_DIR/gtk-4.0"            "$HOME/.config/gtk-4.0"
link "$DOTFILES_DIR/fontconfig"         "$HOME/.config/fontconfig"
link "$DOTFILES_DIR/starship.toml"      "$HOME/.config/starship.toml"
link "$DOTFILES_DIR/chromium-flags.conf" "$HOME/.config/chromium-flags.conf"
link "$DOTFILES_DIR/bashrc"             "$HOME/.config/bashrc"

# Link configs to oxidize current theme directory. 
section "Wiring per-file oxidize theme symlinks"

# gtk-3.0/gtk.css and gtk-4.0/gtk.css are whole-file symlinks into current/
link "$OXIDIZE_CURRENT/gtk.css"          "$HOME/.config/gtk-3.0/gtk.css"
link "$OXIDIZE_CURRENT/gtk.css"          "$HOME/.config/gtk-4.0/gtk.css"

# mako/config is entirely the theme file (no static wrapper)
link "$OXIDIZE_CURRENT/mako.ini"         "$HOME/.config/mako/config"

# niri includes niri-colors.kdl from current/
link "$OXIDIZE_CURRENT/niri-colors.kdl"  "$HOME/.config/niri/niri-colors.kdl"

# btop looks for themes/current.theme in its themes dir
link "$OXIDIZE_CURRENT/btop.theme"       "$HOME/.config/btop/themes/current.theme"

# helix base16_transparent + colors.toml
link "$OXIDIZE_CURRENT/helix.toml"       "$HOME/.config/helix/themes/oxidize.toml"

# Finalize
section "Setting defaults"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
oxidize set aeryn

section "Done"
printf "Next step:\n"
printf "  ${BLD}oxidize set <theme-name>${RST}   — apply your first theme\n"
printf "Available themes in: $DOTFILES_DIR/oxidize/themes/data/\n\n"
printf "Reboot and then start niri-session.\n\n"
read -r -p "Reboot now? [y/N] " _reboot_reply
[[ "$_reboot_reply" =~ ^[Yy]$ ]] && sudo reboot
    
