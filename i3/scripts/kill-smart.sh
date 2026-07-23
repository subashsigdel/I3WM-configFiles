#!/bin/bash
# mod+q: kill focused window as usual, but if it's hosting a tmux session
# (one of the per-window k1/k2/k3... sessions from fish/config.fish), end
# that session too, so a phone attached to it isn't left mirroring a dead window.

winid=$(xprop -root -notype _NET_ACTIVE_WINDOW | awk '{print $5}')
pid=$(xprop -id "$winid" -notype _NET_WM_PID 2>/dev/null | awk '{print $3}')

if [ -n "$pid" ] && [ "$pid" != "0" ]; then
    ttys=$(ps -o tty= --ppid "$pid" 2>/dev/null | tr -d ' ' | grep -v '^?$')
    clients=$(tmux list-clients -F '#{client_tty} #{client_session}' 2>/dev/null)
    for tty in $ttys; do
        session=$(echo "$clients" | awk -v t="/dev/$tty" '$1 == t {print $2}')
        if [ -n "$session" ]; then
            tmux kill-session -t "$session" 2>/dev/null
            break
        fi
    done
fi

i3-msg kill
