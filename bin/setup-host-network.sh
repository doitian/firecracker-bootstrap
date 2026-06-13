#!/usr/bin/env bash
set -euo pipefail

# Usage: setup-host-network.sh [--count N] up|down
#   up   - setup host networking for Firecracker (bridge + tap devices)
#   down - tear down and clean up

BRIDGE="fc-br0"
BRIDGE_IP="172.16.0.1/24"
GUEST_SUBNET="172.16.0.0/24"
TAP_BASE_INDEX=2
TABLE="firecracker"

COUNT=1
CMD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --count)
            COUNT="$2"
            shift 2
            ;;
        -*)
            echo "ERROR: Unknown option: $1" >&2
            exit 1
            ;;
        *)
            CMD="$1"
            shift
            ;;
    esac
done

if [ "${CMD}" != "up" ] && [ "${CMD}" != "down" ]; then
    echo "Usage: $0 [--count N] up|down" >&2
    exit 1
fi

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -lt 1 ]]; then
    echo "ERROR: --count must be a positive integer" >&2
    exit 1
fi

TAP_LAST=$((TAP_BASE_INDEX + COUNT - 1))

# ---- discover host interface ----
HOST_IFACE=$(ip -json route show default 2>/dev/null | jq -r '.[0].dev // empty')
if [ -z "${HOST_IFACE}" ]; then
    echo "ERROR: No default-route interface found" >&2
    exit 1
fi

echo "Command        : ${CMD}"
echo "Host interface : ${HOST_IFACE}"
echo "Bridge         : ${BRIDGE}"
echo "Tap devices    : tap${TAP_BASE_INDEX}..tap${TAP_LAST}"
echo "Guest subnet   : ${GUEST_SUBNET}"
echo "Guest IPs      : 172.16.0.${TAP_BASE_INDEX}..172.16.0.${TAP_LAST}"

# ============================================================
# up
# ============================================================
if [ "${CMD}" = "up" ]; then

    # ---- create bridge ----
    if ! ip link show "${BRIDGE}" &>/dev/null; then
        sudo ip link add name "${BRIDGE}" type bridge
        echo "  -> Created bridge ${BRIDGE}"
    else
        echo "  -> Bridge ${BRIDGE} already exists"
    fi

    if ! ip addr show "${BRIDGE}" | grep -qF "${BRIDGE_IP}"; then
        sudo ip addr add "${BRIDGE_IP}" dev "${BRIDGE}"
        echo "  -> Assigned ${BRIDGE_IP} to ${BRIDGE}"
    fi
    sudo ip link set "${BRIDGE}" up
    echo "  -> Brought up ${BRIDGE}"

    # ---- create tap devices and attach to bridge ----
    TAP_USER="${SUDO_USER:-$USER}"
    for idx in $(seq "${TAP_BASE_INDEX}" "${TAP_LAST}"); do
        tap="tap${idx}"
        if ! ip link show "${tap}" &>/dev/null; then
            sudo ip tuntap add "${tap}" mode tap user "${TAP_USER}"
            echo "  -> Created ${tap} (owner: ${TAP_USER})"
        else
            echo "  -> ${tap} already exists"
        fi
        if ! ip link show "${tap}" | grep -qF "master ${BRIDGE}"; then
            sudo ip addr flush dev "${tap}" 2>/dev/null || true
            sudo ip link set "${tap}" master "${BRIDGE}"
            echo "  -> Attached ${tap} to ${BRIDGE}"
        fi
        sudo ip link set "${tap}" up
    done

    # ---- enable IPv4 forwarding ----
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null

    # ---- nftables ----
    if ! sudo nft list tables ip | grep -qF "${TABLE}"; then
        sudo nft add table ip "${TABLE}"
        sudo nft 'add chain ip '"${TABLE}"' postrouting { type nat hook postrouting priority srcnat; policy accept; }'
        sudo nft 'add chain ip '"${TABLE}"' forward { type filter hook forward priority filter; policy accept; }'
        echo "  -> Created nft table ${TABLE}"
    fi

    if ! sudo nft list chain ip "${TABLE}" postrouting 2>/dev/null | grep -qF "${GUEST_SUBNET}"; then
        sudo nft add rule ip "${TABLE}" postrouting ip saddr "${GUEST_SUBNET}" oifname "${HOST_IFACE}" counter masquerade
        echo "  -> Added NAT masquerade for ${GUEST_SUBNET}"
    else
        echo "  -> NAT masquerade for ${GUEST_SUBNET} already exists"
    fi

    if ! sudo nft list chain ip "${TABLE}" forward 2>/dev/null | grep -qF "${BRIDGE}"; then
        sudo nft add rule ip "${TABLE}" forward iifname "${BRIDGE}" oifname "${HOST_IFACE}" accept
        sudo nft add rule ip "${TABLE}" forward ct state established,related accept
        echo "  -> Added forward rules for ${BRIDGE}"
    else
        echo "  -> Forward rules for ${BRIDGE} already exist"
    fi

    # ---- UFW ----
    if ! sudo ufw status | grep -q "Status: active"; then
        sudo ufw --force enable
        echo "  -> Enabled UFW"
    fi

    if ! sudo ufw status numbered | grep -q "in on ${BRIDGE}"; then
        sudo ufw allow in on "${BRIDGE}"
        echo "  -> Allowed inbound on ${BRIDGE}"
    else
        echo "  -> Inbound on ${BRIDGE} already allowed"
    fi

    echo ""
    echo "Done. Use in Firecracker config:"
    for idx in $(seq "${TAP_BASE_INDEX}" "${TAP_LAST}"); do
        tap="tap${idx}"
        last_octet="$((idx))"
        printf -v mac "06:00:AC:10:00:%02X" "${last_octet}"
        echo "  host_dev_name: ${tap}   guest_mac: ${mac}   ip: 172.16.0.${last_octet}"
    done

# ============================================================
# down
# ============================================================
else
    # ---- delete tap devices ----
    for idx in $(seq "${TAP_BASE_INDEX}" "${TAP_LAST}"); do
        tap="tap${idx}"
        if ip link show "${tap}" &>/dev/null; then
            sudo ip link del "${tap}"
            echo "  -> Deleted ${tap}"
        else
            echo "  -> ${tap} does not exist"
        fi
    done

    # ---- delete bridge ----
    if ip link show "${BRIDGE}" &>/dev/null; then
        sudo ip link del "${BRIDGE}"
        echo "  -> Deleted bridge ${BRIDGE}"
    else
        echo "  -> Bridge ${BRIDGE} does not exist"
    fi

    # ---- remove nftables table ----
    if sudo nft list tables ip | grep -qF "${TABLE}"; then
        sudo nft delete table ip "${TABLE}"
        echo "  -> Deleted nft table ${TABLE}"
    else
        echo "  -> nft table ${TABLE} does not exist"
    fi

    # ---- remove ufw rule ----
    RULE_NUM=$(sudo ufw status numbered | grep "in on ${BRIDGE}" | awk '{print $2}' | tr -d '[]' || true)
    if [ -n "${RULE_NUM}" ]; then
        sudo ufw --force delete "${RULE_NUM}"
        echo "  -> Removed UFW rule for ${BRIDGE}"
    else
        echo "  -> No UFW rule for ${BRIDGE}"
    fi

    echo ""
    echo "Torn down."
fi
