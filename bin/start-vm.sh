#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: start-vm.sh [OPTIONS] <rootfs-tag> <node-index>

Arguments:
  rootfs-tag     Rootfs tag (e.g., alpine)
  node-index     Process index starting from 0 (IP = 172.16.0.<2+index>)

Options:
  --config-only       Generate config only, don't start the VM
  --set KEY=VALUE     Override a config value using a jq path expression.
                      Can be specified multiple times.
                      Examples:
                        --set machine-config.vcpu_count=4
                        --set boot-source.boot_args="reboot=k panic=1 console=ttyS0 quiet"
                        --set drives[0].path_on_host=/custom/path.ext4
  -h, --help          Show this help message
EOF
    exit 0
}

# ---------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------
CONFIG_ONLY=false
OVERRIDES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config-only)
            CONFIG_ONLY=true
            shift
            ;;
        --set)
            OVERRIDES+=("$2")
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        --*)
            echo "ERROR: Unknown option: $1" >&2
            exit 1
            ;;
        -*)
            echo "ERROR: Unknown option: $1" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -ne 2 ]]; then
    echo "ERROR: Expected <rootfs-tag> and <node-index>" >&2
    echo "" >&2
    usage
fi

ROOTFS_TAG="$1"
NODE_INDEX="${2//\{PC_REPLICA_NUM\}/${PC_REPLICA_NUM:-0}}"

if ! [[ "$NODE_INDEX" =~ ^[0-9]+$ ]]; then
    echo "ERROR: node-index must be a non-negative integer, got: $NODE_INDEX" >&2
    exit 1
fi

# ---------------------------------------------------------------
# Locate template config
# ---------------------------------------------------------------
TEMPLATE="rootfs/${ROOTFS_TAG}/config.json"
if [[ ! -f "$TEMPLATE" ]]; then
    echo "ERROR: Template config not found: $TEMPLATE" >&2
    echo "Available tags:" >&2
    for d in rootfs/*/config.json; do
        if [[ -f "$d" ]]; then
            echo "  - $(basename "$(dirname "$d")")" >&2
        fi
    done
    exit 1
fi

# ---------------------------------------------------------------
# Compute node-specific IP and MAC
# ---------------------------------------------------------------
LAST_OCTET=$((2 + NODE_INDEX))
if [[ $LAST_OCTET -gt 254 ]]; then
    echo "ERROR: node-index too large (max 252), got: $NODE_INDEX" >&2
    exit 1
fi

GUEST_IP="172.16.0.${LAST_OCTET}"
GUEST_MAC="06:00:AC:10:00:$(printf "%02X" "$LAST_OCTET")"

# ---------------------------------------------------------------
# Compute disk paths
#
# Each node must boot from its OWN writable rootfs. Sharing a single
# ext4 file across concurrent read-write VMs corrupts the filesystem
# ("Structure needs cleaning" / EFSCORRUPTED). The base image is
# treated as immutable; a per-node copy is created at launch time.
# ---------------------------------------------------------------
BASE_ROOTFS="rootfs/${ROOTFS_TAG}/${ROOTFS_TAG}.ext4"
NODE_ROOTFS="run/${ROOTFS_TAG}-${NODE_INDEX}.ext4"
CONFIG_FILE="run/${ROOTFS_TAG}-${NODE_INDEX}.json"

# ---------------------------------------------------------------
# Build jq filter to modify template
# ---------------------------------------------------------------
JQ_FILTER="
  .\"network-interfaces\"[0].guest_mac = \"${GUEST_MAC}\" |
  .\"network-interfaces\"[0].host_dev_name = \"tap${LAST_OCTET}\" |
  .drives[0].path_on_host = \"${NODE_ROOTFS}\"
"

for override in "${OVERRIDES[@]}"; do
    if [[ ! "$override" =~ = ]]; then
        echo "ERROR: --set value must be in KEY=VALUE format, got: $override" >&2
        exit 1
    fi
    key="${override%%=*}"
    val="${override#*=}"
    val_json=$(jq -n --arg v "$val" '$v | fromjson? // $v')
    JQ_FILTER="${JQ_FILTER} | .${key} = ${val_json}"
done

# ---------------------------------------------------------------
# Generate config
# ---------------------------------------------------------------
CONFIG_JSON=$(jq "${JQ_FILTER}" "$TEMPLATE")

if $CONFIG_ONLY; then
    echo "$CONFIG_JSON"
    exit 0
fi

# ---------------------------------------------------------------
# Start Firecracker
# ---------------------------------------------------------------
if [[ ! -f "$BASE_ROOTFS" ]]; then
    echo "ERROR: Base rootfs not found: $BASE_ROOTFS" >&2
    echo "Bake it first, e.g.: mise run bake-rootfs <kernelfs-dir> ${ROOTFS_TAG}" >&2
    exit 1
fi

# Give this node its own writable disk. Use a reflink (CoW) when the
# filesystem supports it (btrfs/XFS) and fall back to a full copy
# otherwise, so concurrent nodes never share one ext4 file.
echo "Provisioning node disk: ${NODE_ROOTFS} (from ${BASE_ROOTFS})"
mkdir -p "$(dirname "$NODE_ROOTFS")"
cp --reflink=auto -f "$BASE_ROOTFS" "$NODE_ROOTFS"

mkdir -p "$(dirname "$CONFIG_FILE")"
echo "$CONFIG_JSON" > "$CONFIG_FILE"
echo "Config written to: $CONFIG_FILE"

FIRECRACKER_BIN="${FIRECRACKER_BIN:-firecracker}"
if ! command -v "$FIRECRACKER_BIN" &>/dev/null; then
    echo "ERROR: firecracker not found in PATH (set FIRECRACKER_BIN env var to override)" >&2
    exit 1
fi

echo "Starting Firecracker — Node $NODE_INDEX  IP: $GUEST_IP  MAC: $GUEST_MAC  Tap: tap${LAST_OCTET}"
exec "$FIRECRACKER_BIN" --config-file "$CONFIG_FILE" --no-api
