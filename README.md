# I3WM-configFiles

Personal desktop setup: i3wm, polybar, rofi, dunst, xfce4-terminal, tmux, and fish.

## Layout

- `i3/` — i3 config, keybindings, i3blocks config, and status scripts
- `polybar/` — multiple polybar themes/layouts (only one is used at a time, see `polybar/launch.sh`)
- `rofi/` — app launcher, power menu, and keyhint themes
- `dunst/` — notification daemon config
- `terminal/` — xfce4-terminal xfconf export
- `tmux/tmux.conf`
- `fish/` — `config.fish`, `conf.d/`, `functions/`
- `gtk/settings.ini`, `xsettingsd/xsettingsd.conf` — GTK theme (Arc-Dark / Qogir-dark / Qogir-Light cursor)
- `systemd/wake-alarm.service` — system unit bound to `$mod+F12` (stop wake alarm)

## New machine setup

1. Install packages: `i3` `polybar` `rofi` `dunst` `xfce4-terminal` `tmux` `fish` `picom` `feh` `flameshot` `brightnessctl` `i3blocks` `xkblayout-state` `power-profiles-daemon`, the `arc-gtk-theme` / `qogir-icon-theme` / `qogir-cursor-theme` (AUR) packages, `ttf-iosevka-nerd` (polybar font), plus anything referenced by scripts in `i3/scripts/` (e.g. `nordvpn` for the vpn blocklet).
2. Clone this repo, then run `./install.sh` — it symlinks everything into `~/.config/...` (and installs the systemd unit if run with sudo access), backing up any existing files as `*.bak`.
3. Set fish as the login shell: `chsh -s "$(command -v fish)"`.
4. In `i3/config`, the wallpaper path (`feh --bg-fill ...`) is machine-specific — copy over `~/Pictures/wallpaper/` (not tracked in this repo — personal images) and update the path if the filename differs.
5. If using the weather blocklet, put a real OpenWeather API key into `i3/scripts/openweather` / `openweather-city` (currently placeholders).
6. `wake-alarm.service` expects `~/vs/Laptop_sh/wake_alarm.sh` to exist — that script lives outside this repo, bring it over separately.
7. The fish `pinchtab-kill`/`pinchtab-status` functions expect a `pinchtab` install (see `~/vs/pinchtab` on the old machine) — bring that over too if you use it.
8. Log out and start an i3 session.
