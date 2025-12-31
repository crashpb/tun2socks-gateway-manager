#!/bin/bash
# Path: /opt/tun2socks-gateway-manager/scripts/core.sh

BASE_DIR="/opt/tun2socks-gateway-manager"
INSTANCE_NAME=$1
ACTION=${2:-start}

CONFIG_FILE="${BASE_DIR}/conf/${INSTANCE_NAME}.conf"
ID_FILE="${BASE_DIR}/run/${INSTANCE_NAME}.id"
BINARY="${BASE_DIR}/bin/tun2socks-current"

# --- Functions ---

find_free_id() {
    # Scan IDs 10 to 200 for a free slot
    for i in {10..200}; do
        if ! ip link show "t2s$i" > /dev/null 2>&1; then echo "$i"; return 0; fi
    done
    echo "NO_FREE_ID"; return 1
}

get_vars() {
    local id=$1
    TUN_DEV="t2s${id}"
    TUN_IP="10.100.${id}.1"
    TABLE_ID=$((1000 + id))
}

# Auto-detect LAN Subnet (e.g., 172.17.11.0/24)
get_lan_subnet() {
    ip -o -f inet addr show $PHY_IF | awk '{print $4}' | head -1
}

# --- Main Logic ---

if [ "$ACTION" == "start" ]; then
    if [ ! -f "$CONFIG_FILE" ]; then echo "Error: Config not found."; exit 1; fi
    source "$CONFIG_FILE"

    if [[ -z "$PHY_IF" || -z "$PROXY_URL" ]]; then
        echo "Error: Config must have PHY_IF and PROXY_URL."
        exit 1
    fi

    # 1. ID Management
    if [ -f "$ID_FILE" ]; then rm "$ID_FILE"; fi
    MY_ID=$(find_free_id)
    [ "$MY_ID" == "NO_FREE_ID" ] && exit 1
    echo "$MY_ID" > "$ID_FILE"
    get_vars "$MY_ID"

    echo ">>> Starting ${INSTANCE_NAME} (ID: ${MY_ID})"

    # 2. LAN Network Detection
    if [ -z "$LAN_NET" ]; then
        LAN_NET=$(get_lan_subnet)
    fi

    # 3. System Configuration (ARP & Routing Fixes)
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    
    # Disable RP Filter
    sysctl -w net.ipv4.conf.all.rp_filter=0 > /dev/null
    sysctl -w net.ipv4.conf.default.rp_filter=0 > /dev/null
    sysctl -w net.ipv4.conf.$PHY_IF.rp_filter=0 > /dev/null

    # ARP Suppression (Prevents Flux)
    sysctl -w net.ipv4.conf.all.arp_ignore=1 > /dev/null
    sysctl -w net.ipv4.conf.all.arp_announce=2 > /dev/null
    sysctl -w net.ipv4.conf.$PHY_IF.arp_ignore=1 > /dev/null
    sysctl -w net.ipv4.conf.$PHY_IF.arp_announce=2 > /dev/null

    # 4. Interface Setup (IP Alias)
    if [ ! -z "$GATEWAY_IP" ]; then
        ip addr replace $GATEWAY_IP/32 dev $PHY_IF
    fi

    # 5. Create TUN Device
    ip tuntap add dev $TUN_DEV mode tun
    ip addr add $TUN_IP/32 dev $TUN_DEV
    ip link set $TUN_DEV up

    # 6. Routing Table Setup
    # A. Internet -> Tunnel
    ip route add default dev $TUN_DEV table $TABLE_ID
    
    # B. LAN -> Physical Interface (Return Path)
    if [ ! -z "$LAN_NET" ]; then
        ip route add $LAN_NET dev $PHY_IF table $TABLE_ID
    else
        echo "    [WARNING] LAN Subnet detection failed. Traffic may drop."
    fi

    # 7. Policy Routing Rules
    if [ -z "$CLIENT_IP" ]; then
        # MODE A: DEDICATED INTERFACE
        echo "    [MODE] Interface Binding (All traffic entering $PHY_IF)"
        ip rule add iif $PHY_IF lookup $TABLE_ID pref 100
    else
        # MODE B: SHARED INTERFACE
        echo "    [MODE] Source Routing (Client: $CLIENT_IP)"
        ip rule add from $CLIENT_IP lookup $TABLE_ID pref 100
    fi

    # 8. NAT
    iptables -t nat -A POSTROUTING -o $TUN_DEV -j MASQUERADE

    echo "    [OK] Gateway: ${GATEWAY_IP:-N/A} on $PHY_IF"
    echo "    [OK] Proxy:   $PROXY_URL"

    # 9. Launch Tun2Socks
    exec "$BINARY" -device $TUN_DEV -proxy "$PROXY_URL"

elif [ "$ACTION" == "stop" ]; then
    if [ ! -f "$ID_FILE" ]; then exit 0; fi
    MY_ID=$(cat "$ID_FILE")
    get_vars "$MY_ID"
    source "$CONFIG_FILE"
    
    echo ">>> Stopping ${INSTANCE_NAME}"

    iptables -t nat -D POSTROUTING -o $TUN_DEV -j MASQUERADE 2>/dev/null
    
    # Cleanup Rules
    ip rule del iif $PHY_IF lookup $TABLE_ID 2>/dev/null
    if [ ! -z "$CLIENT_IP" ]; then
        ip rule del from $CLIENT_IP lookup $TABLE_ID 2>/dev/null
    fi

    # Cleanup Routes & Device
    ip route flush table $TABLE_ID 2>/dev/null
    ip link delete $TUN_DEV 2>/dev/null
    
    if [ ! -z "$GATEWAY_IP" ]; then
        ip addr del $GATEWAY_IP/32 dev $PHY_IF 2>/dev/null
    fi

    rm "$ID_FILE"
    echo "    [OK] Stopped."

fi
