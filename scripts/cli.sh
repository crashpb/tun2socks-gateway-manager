#!/bin/bash
CONF_DIR="/opt/tun2socks-gateway-manager/conf"
RUN_DIR="/opt/tun2socks-gateway-manager/run"

if [ "$EUID" -ne 0 ]; then echo "Root required."; exit 1; fi

get_latency() {
    local name=$1
    local log="$RUN_DIR/$name.icmp.log"
    if [ ! -f "$log" ]; then echo "-"; return; fi
    local lat=$(grep -oE "Latency(:| Updated:) [0-9]+ms" "$log" | tail -n 1 | grep -oE "[0-9]+ms")
    echo "${lat:-0ms}"
}

print_status() {
    echo "-------------------------------------------------------------------------------------------------------------------------"
    printf "%-12s | %-10s | %-10s | %-15s | %-15s | %-8s | %-20s\n" "NAME" "STATUS" "INTERFACE" "GATEWAY IP" "VIP" "LAT" "PROXY"
    echo "-------------------------------------------------------------------------------------------------------------------------"
    shopt -s nullglob
    for conf in "$CONF_DIR"/*.conf; do
        name=$(basename "$conf" .conf)
        (
            source "$conf"
            local vip_file="$RUN_DIR/$name.vip"
            local lat="-"
            
            if systemctl is-active --quiet "tun2socks@$name"; then
                st="\e[32mRUNNING\e[0m"
                lat=$(get_latency "$name")
            else
                st="\e[31mSTOPPED\e[0m"
            fi
            
            # Get Runtime VIP
            local vip_disp="${ICMP_RES_IP:-N/A}"
            if [ -f "$vip_file" ]; then vip_disp=$(cat "$vip_file"); fi
            
            short_proxy=$(echo $PROXY_URL | cut -c 1-20)
            printf "%-12s | %-19b | %-10s | %-15s | %-15s | %-8s | %-20s\n" \
                   "$name" "$st" "$PHY_IF" "${GATEWAY_IP:-N/A}" "$vip_disp" "$lat" "$short_proxy..."
        )
    done
    echo "-------------------------------------------------------------------------------------------------------------------------"
}

case "$1" in
    start|stop|restart)
        [ -z "$2" ] && echo "Missing name." && exit 1
        systemctl "$1" "tun2socks@$2"
        ;;
    status)
        [ -z "$2" ] && print_status || systemctl status "tun2socks@$2"
        ;;
    log)
        [ -z "$2" ] && echo "Usage: t2s log <name>" && exit 1
        tail -f "$RUN_DIR/$2.icmp.log"
        ;;
    *)
        echo "Usage: t2s {start|stop|restart|status|log} [config_name]"
        ;;
esac
