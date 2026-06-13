#!/usr/bin/env bash
set -euo pipefail

# Usage: setup-host-network.sh up|down
#   up   - setup host networking for Firecracker
#   down - tear down and clean up

TAP_DEV="tap2"
TAP_IP="172.16.0.1/24"
GUEST_IP="172.16.0.2"
TABLE="firecracker"

CMD="${1:-}"

if [ "${CMD}" != "up" ] && [ "${CMD}" != "down" ]; then
    echo "Usage: $0 up|down" >&2
    exit 1
fi

# ---- discover host interface ----
HOST_IFACE=$(ip -json route show default 2>/dev/null | jq -r '.[0].dev // empty')
if [ -z "${HOST_IFACE}" ]; then
    echo "ERROR: No default-route interface found" >&2
    exit 1
fi

echo "Command        : ${CMD}"
echo "Host interface : ${HOST_IFACE}"
echo "Tap device     : ${TAP_DEV}"

# ============================================================
# up
# ============================================================
if [ "${CMD}" = "up" ]; then
    echo "Tap IP         : ${TAP_IP}"
    echo "Guest IP       : ${GUEST_IP}"

    # ---- create tap device ----
    if ! ip link show "${TAP_DEV}" &>/dev/null; then
        sudo ip tuntap add "${TAP_DEV}" mode tap
        echo "  -> Created ${TAP_DEV}"
    else
        echo "  -> ${TAP_DEV} already exists"
    fi

    if ! ip addr show "${TAP_DEV}" | grep -qF "${TAP_IP}"; then
        sudo ip addr add "${TAP_IP}" dev "${TAP_DEV}"
        echo "  -> Assigned ${TAP_IP} to ${TAP_DEV}"
    fi
    sudo ip link set "${TAP_DEV}" up

    # ---- enable IPv4 forwarding ----
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null

    # ---- nftables ----
    if ! sudo nft list tables ip | grep -qF "${TABLE}"; then
        sudo nft add table ip "${TABLE}"
        sudo nft 'add chain ip '"${TABLE}"' postrouting { type nat hook postrouting priority srcnat; policy accept; }'
        sudo nft 'add chain ip '"${TABLE}"' forward { type filter hook forward priority filter; policy accept; }'
        echo "  -> Created nft table ${TABLE}"
    fi

    if ! sudo nft list chain ip "${TABLE}" postrouting 2>/dev/null | grep -qF "${GUEST_IP}"; then
        sudo nft add rule ip "${TABLE}" postrouting ip saddr "${GUEST_IP}" oifname "${HOST_IFACE}" counter masquerade
        echo "  -> Added NAT masquerade for ${GUEST_IP}"
    else
        echo "  -> NAT masquerade for ${GUEST_IP} already exists"
    fi

    if ! sudo nft list chain ip "${TABLE}" forward 2>/dev/null | grep -qF "${TAP_DEV}"; then
        sudo nft add rule ip "${TABLE}" forward iifname "${TAP_DEV}" oifname "${HOST_IFACE}" accept
        sudo nft add rule ip "${TABLE}" forward ct state established,related accept
        echo "  -> Added forward rules for ${TAP_DEV}"
    else
        echo "  -> Forward rules for ${TAP_DEV} already exist"
    fi

    # ---- UFW ----
    if ! sudo ufw status | grep -q "Status: active"; then
        sudo ufw --force enable
        echo "  -> Enabled UFW"
    fi

    if ! sudo ufw status numbered | grep -q "in on ${TAP_DEV}"; then
        sudo ufw allow in on "${TAP_DEV}"
        echo "  -> Allowed inbound on ${TAP_DEV}"
    else
        echo "  -> Inbound on ${TAP_DEV} already allowed"
    fi

    echo ""
    echo "Done. Use in Firecracker config:"
    echo "  guest_mac: 06:00:AC:10:00:02"
    echo "  host_dev_name: ${TAP_DEV}"

# ============================================================
# down
# ============================================================
else
    # ---- delete tap device ----
    if ip link show "${TAP_DEV}" &>/dev/null; then
        sudo ip link del "${TAP_DEV}"
        echo "  -> Deleted ${TAP_DEV}"
    else
        echo "  -> ${TAP_DEV} does not exist"
    fi

    # ---- remove nftables table ----
    if sudo nft list tables ip | grep -qF "${TABLE}"; then
        sudo nft delete table ip "${TABLE}"
        echo "  -> Deleted nft table ${TABLE}"
    else
        echo "  -> nft table ${TABLE} does not exist"
    fi

    # ---- remove ufw rule ----
    RULE_NUM=$(sudo ufw status numbered | grep "in on ${TAP_DEV}" | awk '{print $2}' | tr -d '[]' || true)
    if [ -n "${RULE_NUM}" ]; then
        sudo ufw --force delete "${RULE_NUM}"
        echo "  -> Removed UFW rule for ${TAP_DEV}"
    else
        echo "  -> No UFW rule for ${TAP_DEV}"
    fi

    echo ""
    echo "Torn down."
fi
