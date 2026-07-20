function pinchtab-kill --wraps='sudo pkill -f pinchtab-safe && echo "PinchTab stopped"' --description 'alias pinchtab-kill=sudo pkill -f pinchtab-safe && echo "PinchTab stopped"'
    sudo pkill -f pinchtab-safe && echo "PinchTab stopped" $argv
end
