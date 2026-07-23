# I3WM-configFiles

Personal desktop setup: i3wm, polybar, rofi, dunst, xfce4-terminal, tmux, and fish.

## Layout

- `i3/` — i3 config, keybindings, i3blocks config, and status scripts
- `polybar/` — multiple polybar themes/layouts (only one is used at a time, see `polybar/launch.sh`); `polybar/rice/` is the default, a single top bar with dot-style workspace indicators
- `picom/picom.conf` — compositor config: window transparency, background blur, rounded corners. Uses the `glx` backend (not `xrender` — xrender does compositing in software on the X server's CPU and pegs a core once blur/corners are enabled, causing system-wide input/scroll lag). Rounded corners apply to all windows (cheap on `glx`); background blur is scoped to `kitty` only via `blur-background-exclude` (`dual_kawase` blur is the expensive effect, so it's kept off everything else). `unredir-if-possible = true` lets fullscreen windows (video, games) bypass the compositor entirely.
- `kitty/kitty.conf` — primary terminal, pastel dark theme, translucent background
- `fastfetch/config.jsonc` — system-info fetch tool, ASCII distro logo (no image)
- `rofi/` — app launcher, power menu, and keyhint themes
- `dunst/` — notification daemon config
- `terminal/` — xfce4-terminal xfconf export (kept as a non-transparent fallback terminal)
- `xfce4/helpers.rc` — sets kitty as the XFCE-wide preferred terminal emulator (`exo-open --launch TerminalEmulator`), so Thunar's "Open Terminal Here" and similar launch kitty instead of xfce4-terminal
- `flameshot/flameshot.ini` — `useX11LegacyScreenshot=true`; needed because current flameshot builds default to the xdg-desktop-portal screenshot backend, which has no backend on i3 (there's no portal implementation running) — without this, `flameshot gui` fails immediately with "Screenshot aborted" / "xdg-desktop-portal backend did not respond". This setting forces flameshot back to Qt's native X11 capture, bound to `Ctrl+Shift+S` in `i3/config`.
- `tmux/tmux.conf`
- `fish/` — `config.fish`, `conf.d/`, `functions/`
- `gtk/settings.ini`, `xsettingsd/xsettingsd.conf` — GTK theme (Arc-Dark / Qogir-dark / Qogir-Light cursor)
- `systemd/wake-alarm.service` — system unit bound to `$mod+F12` (stop wake alarm)

## New machine setup

1. Install packages: `i3` `polybar` `rofi` `dunst` `xfce4-terminal` `kitty` `fastfetch` `tmux` `fish` `picom` `feh` `flameshot` `brightnessctl` `i3blocks` `xkblayout-state` `power-profiles-daemon`, the `arc-gtk-theme` / `qogir-icon-theme` / `qogir-cursor-theme` (AUR) packages, `ttf-iosevka-nerd` (polybar/kitty/bar font), plus anything referenced by scripts in `i3/scripts/` (e.g. `nordvpn` for the vpn blocklet).
2. Clone this repo, then run `./install.sh` — it symlinks everything into `~/.config/...` (and installs the systemd unit if run with sudo access), backing up any existing files as `*.bak`.
3. Set fish as the login shell: `chsh -s "$(command -v fish)"`.
4. In `i3/config`, the wallpaper path (`feh --bg-fill ...`) is machine-specific — copy over `~/Pictures/wallpaper/` (not tracked in this repo — personal images) and update the path if the filename differs.
5. If using the weather blocklet, put a real OpenWeather API key into `i3/scripts/openweather` / `openweather-city` (currently placeholders).
6. `wake-alarm.service` expects `~/vs/Laptop_sh/wake_alarm.sh` to exist — that script lives outside this repo, bring it over separately.
7. The fish `pinchtab-kill`/`pinchtab-status` functions expect a `pinchtab` install (see `~/vs/pinchtab` on the old machine) — bring that over too if you use it.
8. Log out and start an i3 session.

## Switching polybar themes

`polybar/launch.sh --<theme>` (e.g. `--rice`, `--hack`, `--material`, run with no args to list all). The active theme is set in `i3/config`'s `exec_always ... polybar/launch.sh` line.
