#!/bin/bash
CONF_DIR="/opt/tun2socks/conf"

if [ "$EUID" -ne 0 ]; then echo "Root required."; exit 1; fi

print_status() {
    echo "---------------------------------------------------------------------------------------"
    printf "%-12s | %-10s | %-10s | %-15s | %-20s\n" "NAME" "STATUS" "INTERFACE" "GATEWAY IP" "PROXY"
    echo "---------------------------------------------------------------------------------------"
    shopt -s nullglob
    for conf in "$CONF_DIR"/*.conf; do
        name=$(basename "$conf" .conf)
        (
            source "$conf"
            if systemctl is-active --quiet "tun2socks@$name"; then
                st="\e[32mRUNNING\e[0m"
            else
                st="\e[31mSTOPPED\e[0m"
            fi
            short_proxy=$(echo $PROXY_URL | cut -c 1-20)
            printf "%-12s | %-19b | %-10s | %-15s | %-20s\n" "$name" "$st" "$PHY_IF" "${GATEWAY_IP:-N/A}" "$short_proxy..."
        )
    done
    echo "---------------------------------------------------------------------------------------"
}

case "$1" in
    start|stop|restart)
        [ -z "$2" ] && echo "Missing name." && exit 1
        systemctl "$1" "tun2socks@$2"
        ;;
    status)
        [ -z "$2" ] && print_status || systemctl status "tun2socks@$2"
        ;;
    *)
        echo "Usage: t2s {start|stop|restart|status} [config_name]"
        ;;
esac