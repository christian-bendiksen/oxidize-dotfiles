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

# Pre-flight
section "Pre-flight checks"

[[ "$EUID" -eq 0 ]] && die "Do not run as root."

# check for git
if ! command -v git &>/dev/null; then
    die "'git' not found. Install it before running this script."
fi
ok "found git ($(command -v git))"

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

mkdir -p "$HOME/.local/bin"

# Clone oxidize-dotfiles if not already present
section "Setting up oxidize-dotfiles"

if [[ -d "$DOTFILES_DIR/.git" ]]; then
    info "Updating existing oxidize-dotfiles clone..."
    git -C "$DOTFILES_DIR" pull --ff-only
else
    info "Cloning oxidize-dotfiles -> $DOTFILES_DIR"
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
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

# Note: kitty, alacritty, waybar, and fuzzel use in-file include/import
# directives with ~/.config/oxidize/themes/current/... which the shell/app
# expands at runtime — no per-file symlinks needed for those.

# Done
section "Done"

printf "\n${GRN}${BLD}Installation complete.${RST}\n\n"
printf "Runtime dependencies (install via pkgset):\n"
printf "  niri, waybar, kitty, alacritty, mako, btop, starship,\n"
printf "  fuzzel, walker, awww, brightnessctl, playerctl, notify-send\n\n"
printf "Next step:\n"
printf "  ${BLD}oxidize set <theme-name>${RST}   — apply your first theme\n"
printf "Available themes in: $DOTFILES_DIR/oxidize/themes/data/\n\n"
    
