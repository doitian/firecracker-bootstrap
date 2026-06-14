#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: copy-ssh-keys.sh --count N

Copy the first SSH public key from ssh-agent to root@172.16.0.<2..2+N-1>.
Password: root

Options:
  --count N     Number of nodes (default: 1)
  -h, --help    Show this help message
EOF
    exit 0
}

COUNT=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --count)
            COUNT="$2"
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
            echo "ERROR: Unexpected argument: $1" >&2
            exit 1
            ;;
    esac
done

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -lt 1 ]]; then
    echo "ERROR: --count must be a positive integer" >&2
    exit 1
fi

PUBKEY=$(ssh-add -L 2>/dev/null | head -n1)
if [[ -z "$PUBKEY" ]]; then
    echo "ERROR: No keys found in ssh-agent. Run: ssh-add" >&2
    exit 1
fi

ASKPASS_SCRIPT=$(mktemp)
trap 'rm -f "$ASKPASS_SCRIPT"' EXIT
cat > "$ASKPASS_SCRIPT" <<'ENDSCRIPT'
#!/bin/sh
printf '%s\n' root
ENDSCRIPT
chmod +x "$ASKPASS_SCRIPT"

SSH_OPTS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -T
)

echo "Key: $(echo "$PUBKEY" | awk '{print $3}')"
echo "Nodes: $COUNT"
echo ""

for idx in $(seq 0 $((COUNT - 1))); do
    ip="172.16.0.$((2 + idx))"
    echo "  -> root@$ip ..."
    echo "$PUBKEY" | SSH_ASKPASS="$ASKPASS_SCRIPT" setsid ssh "${SSH_OPTS[@]}" "root@$ip" \
        'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys'
    echo "    done"
done

echo ""
echo "Done."
