fish_add_path ~/.local/bin
if status is-interactive && not set -q TMUX
    if set -q SSH_CLIENT
        # Phone: attach to whatever sessions exist, just detach on close
        tmux attach-session 2>/dev/null
        or echo "No sessions running. Open a terminal on your laptop first."
    else
        # Laptop: each terminal gets its own session k1, k2, k3...
        set -l i 1
        while tmux has-session -t k$i 2>/dev/null
            set i (math $i + 1)
        end
        set -l sname k$i
        tmux new-session -s $sname
        tmux kill-session -t $sname 2>/dev/null
    end
end
if status is-interactive
    # Commands to run in interactive sessions can go here
end
set -g fish_greeting ""

# >>> Minimal Conda setup (no auto-activate base) >>>
if test -f /home/subash/anaconda3/etc/fish/conf.d/conda.fish
    . /home/subash/anaconda3/etc/fish/conf.d/conda.fish
end

# <<< Minimal Conda setup <<<

function play_error_sound --on-event fish_postexec
    if test $status -ne 0
        pkill -f "pw-play" 2>/dev/null
        pw-play --volume 0.2 ~/sounds/fawww.wav &
    end
end
set -gx PATH /home/subash/.tnr/bin $PATH


# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
if test -f /home/subash/miniforge3/bin/conda
    eval /home/subash/miniforge3/bin/conda "shell.fish" "hook" $argv | source
else
    if test -f "/home/subash/miniforge3/etc/fish/conf.d/conda.fish"
        . "/home/subash/miniforge3/etc/fish/conf.d/conda.fish"
    else
        set -x PATH "/home/subash/miniforge3/bin" $PATH
    end
end
# <<< conda initialize <<<

