Tun2Socks Gateway Manager
=========================

A Bash-based wrapper for managing multiple Tun2Socks instances on a single Linux host. It utilizes Policy Based Routing (PBR) and SystemD to manage transparent SOCKS5 tunneling for specific interfaces or clients.
The main motivation for creating this project was to enable the use of unsupported VPN protocols on any firewall appliance. Once the proxies are set up properly, they can be used by your firewall of choice as an upstream gateway and referenced in routing rules.

Features
--------

* **Policy Based Routing:** Routes traffic to tunnels based on source IP or ingress interface.
* **Multi-Gateway Support:** Run multiple isolated instances simultaneously.
* **SystemD Integration:** Standard service management (``systemctl start/stop/enable``).
* **ARP Flux Mitigation:** Automatically applies kernel parameters to prevent ARP issues on multi-homed VMs.

Prerequisites
-------------

* **OS:** Linux (Tested on Linux Mint 21 / Ubuntu 22.04 LTS, Kernel 5.15+)
* **Dependencies:** ``iproute2``, ``iptables``, ``curl``/``wget``.
* **Core Binary:** This wrapper requires ``tun2socks``.
    * Download ``tun2socks-linux-amd64`` from the official repository: `xjasonlyu/tun2socks <https://github.com/xjasonlyu/tun2socks>`_.

Installation
------------

1. Clone the repository::

    git clone https://github.com/crashpb/tun2socks-gateway-manager.git
    cd tun2socks-manager

2. Run the installer::

    sudo ./install.sh

3. Install the binary::

    # Download the release matching your architecture and place it in bin/
    sudo cp tun2socks-linux-amd64 /opt/tun2socks/bin/tun2socks-current
    sudo chmod +x /opt/tun2socks/bin/tun2socks-current

Configuration
-------------

Configuration files are stored in ``/opt/tun2socks/conf/``. Files should be named ``<instance_name>.conf``.

Configuration Variables
~~~~~~~~~~~~~~~~~~~~~~~

**PHY_IF** (Required)
    The physical network interface to bind (e.g., ``ens192``).

**PROXY_URL** (Required)
    Upstream proxy URL (e.g., ``socks5://192.168.1.50:1080``).

**GATEWAY_IP** (Optional)
    Adds a secondary IP alias to the interface.

**CLIENT_IP** (Optional)
    If set, enables Source Routing mode (filters by source IP).

**LAN_NET** (Optional)
    Manually defines LAN subnet if auto-detection fails.

Routing Modes
-------------

1. Dedicated Interface Mode (Recommended)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Used when the VM has a dedicated virtual NIC (e.g., ``ens224``) for the gateway. All traffic entering this interface is routed to the tunnel.

.. code:: ini

    PHY_IF=ens224
    GATEWAY_IP=10.1.0.5
    PROXY_URL=socks5://192.168.240.112:10808
    # CLIENT_IP is undefined

2. Source Routing Mode (Shared Interface)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Used when a single NIC (e.g., ``ens192``) handles multiple gateways. Routing is filtered by the source IP of the client.

.. code:: ini

    PHY_IF=ens192
    GATEWAY_IP=10.1.0.5
    CLIENT_IP=10.1.0.55
    PROXY_URL=socks5://192.168.240.112:10808

Usage
-----

Manage Instances::

    # Start an instance named 'ps5' (reads conf/ps5.conf)
    sudo t2s start ps5

    # Stop an instance
    sudo t2s stop ps5

    # View status of all instances
    sudo t2s status

Enable on Boot::

    sudo systemctl enable tun2socks@ps5

Troubleshooting
---------------

* **Logs:** ``journalctl -u tun2socks@<name> -f``
* **Connectivity:** If clients cannot connect, clear the client's ARP cache (``arp -d *`` or ``ip neigh flush all``). The script automatically sets ``arp_ignore=1`` to prevent ARP flux.
