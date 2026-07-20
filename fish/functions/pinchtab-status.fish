function pinchtab-status --wraps='pgrep -f pinchtab-safe && echo "Running" || echo "Stopped"' --description 'alias pinchtab-status=pgrep -f pinchtab-safe && echo "Running" || echo "Stopped"'
    pgrep -f pinchtab-safe && echo "Running" || echo "Stopped" $argv
end
