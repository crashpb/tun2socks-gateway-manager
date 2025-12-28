# Tun2Socks Multi-Gateway Manager
**Documentation & Configuration Reference**

## 1. The Goal
To run multiple SOCKS5 gateways on a single Linux VM, allowing different clients on the LAN to use different proxies (Waydroid, External, etc.) transparently, supporting both TCP and UDP.
The main motivation for creating this project was to enable the use of unsupported VPN protocols on any firewall appliance. Once the proxies are set up properly, they can be used by your firewall of choice as an upstream gateway and referenced in routing rules.

## 2. The Architecture
We utilize **Policy Based Routing (PBR)**. Traffic is routed to specific tunnels based on which physical interface it enters, or which client IP sent it.

## 3. Configuration Reference
Config files are located in `/opt/tun2socks/conf/NAME.conf`.

### Required Variables
| Variable | Description | Example |
| :--- | :--- | :--- |
| `PHY_IF` | The Physical Network Interface to bind to. | `ens192`, `ens224` |
| `PROXY_URL` | The upstream proxy URL. Supports socks5/http. | `socks5://192.168.1.50:1080` |

### Optional Variables
| Variable | Description | Example |
| :--- | :--- | :--- |
| `GATEWAY_IP` | Adds this IP as an alias to the interface. | `10.1.0.5` |
| `CLIENT_IP` | **(Mode B Only)** If set, filters by Source IP. | `10.1.0.55` |
| `LAN_NET` | Manually define LAN subnet if auto-detection fails. | `10.1.0.0/24` |

## 4. Operation Modes

### Mode A: Dedicated Interface (Recommended)
**Use this if:** You have a dedicated Virtual NIC (e.g., `ens224`).
* **Config:** `PHY_IF=ens224`, `CLIENT_IP` is empty.
* **Logic:** All traffic on this interface goes to the tunnel.

### Mode B: Shared Interface (Source Routing)
**Use this if:** You only have one NIC (`ens192`) but need multiple gateways.
* **Config:** `PHY_IF=ens192`, `CLIENT_IP=10.1.0.55`.
* **Logic:** Only traffic FROM `CLIENT_IP` goes to the tunnel.

## 5. Troubleshooting
* **Clients can't reach Gateway?** Likely "ARP Flux". The script automatically sets `arp_ignore=1`. Try clearing client ARP cache.

* **Service Fails?** Check logs: `journalctl -u tun2socks@NAME -f`

