#!/bin/bash
# Path: /opt/tun2socks-gateway-manager/scripts/core.sh

BASE_DIR="/opt/tun2socks-gateway-manager"
INSTANCE_NAME=$1
ACTION=${2:-start}

CONFIG_FILE="${BASE_DIR}/conf/${INSTANCE_NAME}.conf"
ID_FILE="${BASE_DIR}/run/${INSTANCE_NAME}.id"
VIP_FILE="${BASE_DIR}/run/${INSTANCE_NAME}.vip"
BINARY="${BASE_DIR}/bin/tun2socks-current"
BINARY_ICMP="${BASE_DIR}/bin/icmp_responder"
LOG_ICMP="${BASE_DIR}/run/${INSTANCE_NAME}.icmp.log"
PID_ICMP="${BASE_DIR}/run/${INSTANCE_NAME}.icmp.pid"

# Firewall Tag (Prevents deleting manual rules)
T2S_COMMENT="t2s:${INSTANCE_NAME}"

# Dynamic VIP Pool
VIP_PREFIX="10.200.0"
VIP_START=10
VIP_END=250

# --- Functions ---

find_free_id() {
    for i in {10..200}; do
        if ! ip link show "t2s$i" > /dev/null 2>&1; then echo "$i"; return 0; fi
    done
    echo "NO_FREE_ID"; return 1
}

find_free_vip() {
    # Scan configs to avoid static IP collisions
    local reserved_ips=$(grep -r "ICMP_RES_IP=" ${BASE_DIR}/conf/ | cut -d= -f2 | tr -d ' "')

    for i in $(seq $VIP_START $VIP_END); do
        local candidate="${VIP_PREFIX}.${i}"
        if ip route show table local | grep -q "$candidate"; then continue; fi
        if echo "$reserved_ips" | grep -q "$candidate"; then continue; fi
        echo "$candidate"; return 0
    done
    echo "NO_FREE_VIP"; return 1; 
}

get_vars() {
    local id=$1
    TUN_DEV="t2s${id}"
    TUN_IP="10.100.${id}.1"
    TABLE_ID=$((1000 + id))
}

get_lan_subnet() {
    ip -o -f inet addr show $PHY_IF | awk '{print $4}' | head -1
}

clean_firewall() {
    # 1. Clean Gateway Muzzle
    if [ ! -z "$GATEWAY_IP" ]; then
        while iptables -D INPUT -d "$GATEWAY_IP" -p icmp --icmp-type 8 -m comment --comment "$T2S_COMMENT" -j DROP 2>/dev/null; do :; done
        while iptables -t raw -D PREROUTING -d "$GATEWAY_IP" -p icmp --icmp-type 8 -m comment --comment "$T2S_COMMENT" -j DROP 2>/dev/null; do :; done
    fi
    
    # 2. Clean VIP Muzzle
    local target_vip="$ICMP_RES_IP"
    if [ -f "$VIP_FILE" ]; then target_vip=$(cat "$VIP_FILE"); fi
    
    if [ ! -z "$target_vip" ]; then
        while iptables -D INPUT -d "$target_vip" -p icmp --icmp-type 8 -m comment --comment "$T2S_COMMENT" -j DROP 2>/dev/null; do :; done
        while iptables -D OUTPUT -s "$target_vip" -p icmp --icmp-type 0 -m mark ! --mark 100 -m comment --comment "$T2S_COMMENT" -j DROP 2>/dev/null; do :; done
    fi

    # 3. Clean MSS Clamping
    local mss=${MSS_VAL:-1300}
    while iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $mss -m comment --comment "$T2S_COMMENT" 2>/dev/null; do :; done
    while iptables -t mangle -D PREROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $mss -m comment --comment "$T2S_COMMENT" 2>/dev/null; do :; done
}

cleanup_responder() {
    if [ -f "$PID_ICMP" ]; then 
        kill -9 $(cat "$PID_ICMP") 2>/dev/null
        rm "$PID_ICMP"
    fi
    pkill -9 -f "icmp_responder -c $CONFIG_FILE"
}

# --- Main Logic ---

if [ "$ACTION" == "start" ]; then
    if [ ! -f "$CONFIG_FILE" ]; then echo "Error: Config not found."; exit 1; fi
    source "$CONFIG_FILE"

    if [[ -z "$PHY_IF" || -z "$PROXY_URL" ]]; then
        echo "Error: Config must have PHY_IF and PROXY_URL."
        exit 1
    fi

    cleanup_responder
    clean_firewall

    # 1. ID Management
    if [ -f "$ID_FILE" ]; then rm "$ID_FILE"; fi
    MY_ID=$(find_free_id)
    [ "$MY_ID" == "NO_FREE_ID" ] && exit 1
    echo "$MY_ID" > "$ID_FILE"
    get_vars "$MY_ID"

    echo ">>> Starting ${INSTANCE_NAME} (ID: ${MY_ID})"

    # 2. VIP Allocation
    ACTUAL_VIP=""
    if [ ! -z "$ICMP_RES_IP" ]; then
        ACTUAL_VIP="$ICMP_RES_IP"
    else
        ACTUAL_VIP=$(find_free_vip)
        [ "$ACTUAL_VIP" == "NO_FREE_VIP" ] && echo "FATAL: No free VIPs." && exit 1
    fi
    echo "$ACTUAL_VIP" > "$VIP_FILE"

    # 3. System Configuration
    if [ -z "$LAN_NET" ]; then LAN_NET=$(get_lan_subnet); fi
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    sysctl -w net.ipv4.conf.all.rp_filter=0 > /dev/null
    sysctl -w net.ipv4.conf.$PHY_IF.rp_filter=0 > /dev/null
    
    # ARP Suppression
    sysctl -w net.ipv4.conf.$PHY_IF.arp_ignore=1 > /dev/null
    sysctl -w net.ipv4.conf.$PHY_IF.arp_announce=2 > /dev/null

    # 4. Interface Setup
    if [ ! -z "$GATEWAY_IP" ]; then
        ip addr replace $GATEWAY_IP/32 dev $PHY_IF
    fi

    # 5. Create TUN Device
    ip tuntap add dev $TUN_DEV mode tun
    ip link set $TUN_DEV mtu 1500
    ip addr add $TUN_IP/32 dev $TUN_DEV
    ip link set $TUN_DEV up

    # 6. Routing Table Setup
    ip route add default dev $TUN_DEV table $TABLE_ID
    if [ ! -z "$LAN_NET" ]; then
        ip route add $LAN_NET dev $PHY_IF table $TABLE_ID
    fi

    # 7. VIP Routing (Local)
    if [ ! -z "$ACTUAL_VIP" ]; then 
        ip route replace local $ACTUAL_VIP dev lo
        ip rule add to $ACTUAL_VIP lookup main pref 91 2>/dev/null || true
    fi
    if [ ! -z "$GATEWAY_IP" ]; then
        ip rule add to $GATEWAY_IP lookup main pref 90 2>/dev/null || true
    fi

    # 8. Policy Routing Rules
    if [ -z "$CLIENT_IP" ]; then
        # MODE A: DEDICATED INTERFACE
        ip rule add iif $PHY_IF lookup $TABLE_ID pref 100
    else
        # MODE B: SHARED INTERFACE
        ip rule add from $CLIENT_IP lookup $TABLE_ID pref 100
    fi

    # 9. Firewall & NAT
    iptables -t nat -A POSTROUTING -o $TUN_DEV -j MASQUERADE
    
    # MSS Clamping (Fixes SSL/TLS hangs)
    MSS=${MSS_VAL:-1300}
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS -m comment --comment "$T2S_COMMENT"
    iptables -t mangle -A PREROUTING -i $PHY_IF -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS -m comment --comment "$T2S_COMMENT"

    # Kernel Muzzle (For Responder)
    if [ ! -z "$ACTUAL_VIP" ]; then
        iptables -I OUTPUT -s $ACTUAL_VIP -p icmp --icmp-type 0 -m mark ! --mark 100 -m comment --comment "$T2S_COMMENT" -j DROP
    elif [ ! -z "$GATEWAY_IP" ]; then
        iptables -I INPUT -d $GATEWAY_IP -p icmp --icmp-type 8 -m comment --comment "$T2S_COMMENT" -j DROP
    fi

    # 10. Start Responder
    if [ -f "$BINARY_ICMP" ]; then
         "$BINARY_ICMP" -c "$CONFIG_FILE" -i "$PHY_IF" -e "$TUN_DEV" -g "$TUN_IP" -v "$ACTUAL_VIP" -l "$LOG_ICMP" &
         echo $! > "$PID_ICMP"
    fi

    echo "    [OK] Gateway: ${GATEWAY_IP:-N/A} (VIP: $ACTUAL_VIP)"
    
    # 11. Launch Tun2Socks
    exec "$BINARY" -device $TUN_DEV -proxy "$PROXY_URL"

elif [ "$ACTION" == "stop" ]; then
    if [ ! -f "$ID_FILE" ]; then exit 0; fi
    MY_ID=$(cat "$ID_FILE")
    get_vars "$MY_ID"
    source "$CONFIG_FILE"
    
    ACTUAL_VIP=""
    if [ -f "$VIP_FILE" ]; then ACTUAL_VIP=$(cat "$VIP_FILE"); fi

    echo ">>> Stopping ${INSTANCE_NAME}"

    cleanup_responder
    clean_firewall
    iptables -t nat -D POSTROUTING -o $TUN_DEV -j MASQUERADE 2>/dev/null
    
    # Cleanup Rules
    ip rule del iif $PHY_IF lookup $TABLE_ID 2>/dev/null
    if [ ! -z "$CLIENT_IP" ]; then ip rule del from $CLIENT_IP lookup $TABLE_ID 2>/dev/null; fi
    if [ ! -z "$ACTUAL_VIP" ]; then 
        ip route del local $ACTUAL_VIP dev lo 2>/dev/null
        ip rule del to $ACTUAL_VIP lookup main 2>/dev/null
    fi
    if [ ! -z "$GATEWAY_IP" ]; then ip rule del to $GATEWAY_IP lookup main 2>/dev/null; fi

    # Cleanup Routes & Device
    ip route flush table $TABLE_ID 2>/dev/null
    ip link delete $TUN_DEV 2>/dev/null
    
    if [ ! -z "$GATEWAY_IP" ]; then ip addr del $GATEWAY_IP/32 dev $PHY_IF 2>/dev/null; fi

    rm "$ID_FILE" "$VIP_FILE" 2>/dev/null
    echo "    [OK] Stopped."
fi
