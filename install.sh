#!/usr/bin/env bash
# Symlinks these dotfiles into place. Existing files are backed up with a .bak suffix.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

link() {
    local src="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        mv "$dest" "$dest.bak"
        echo "backed up $dest -> $dest.bak"
    fi
    ln -sfn "$src" "$dest"
    echo "linked $dest -> $src"
}

link "$REPO_DIR/i3"      "$HOME/.config/i3"
link "$REPO_DIR/polybar" "$HOME/.config/polybar"
link "$REPO_DIR/dunst/dunstrc" "$HOME/.config/dunst/dunstrc"
link "$REPO_DIR/picom/picom.conf" "$HOME/.config/picom/picom.conf"
link "$REPO_DIR/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
link "$REPO_DIR/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
link "$REPO_DIR/flameshot/flameshot.ini" "$HOME/.config/flameshot/flameshot.ini"

for f in "$REPO_DIR"/rofi/*.rasi; do
    link "$f" "$HOME/.config/rofi/$(basename "$f")"
done

link "$REPO_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"

link "$REPO_DIR/fish/config.fish" "$HOME/.config/fish/config.fish"
for f in "$REPO_DIR"/fish/conf.d/*; do
    link "$f" "$HOME/.config/fish/conf.d/$(basename "$f")"
done
for f in "$REPO_DIR"/fish/functions/*; do
    link "$f" "$HOME/.config/fish/functions/$(basename "$f")"
done

link "$REPO_DIR/terminal/xfce4-terminal.xml" "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml"
link "$REPO_DIR/xfce4/helpers.rc" "$HOME/.config/xfce4/helpers.rc"

link "$REPO_DIR/gtk/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
link "$REPO_DIR/xsettingsd/xsettingsd.conf" "$HOME/.config/xsettingsd/xsettingsd.conf"

link "$REPO_DIR/xresources/Xresources" "$HOME/.Xresources"

if [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
    sudo cp "$REPO_DIR/systemd/wake-alarm.service" /etc/systemd/system/wake-alarm.service
    sudo systemctl daemon-reload
    echo "installed and reloaded wake-alarm.service (not enabled; run: sudo systemctl enable wake-alarm.service)"
else
    echo "skipped wake-alarm.service (needs sudo) — install manually:"
    echo "  sudo cp $REPO_DIR/systemd/wake-alarm.service /etc/systemd/system/ && sudo systemctl daemon-reload"
fi

echo "Done. Remember to install i3, polybar, xfce4-terminal, tmux, fish, dunst, rofi, picom, feh, flameshot, brightnessctl, xkblayout-state, power-profiles-daemon, nordvpn (as used) via your package manager, and set fish as your login shell (chsh -s $(command -v fish))."
