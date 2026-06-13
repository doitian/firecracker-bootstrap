FROM alpine:3

RUN <<EOR
set -euo pipefail

apk add --update-cache openrc
rm -rf /var/cache/apk/*

sed -i '/^#ttyS0::respawn:/s/^#//' /etc/inittab

echo "root:root" | chpasswd

cat <<'SCRIPT' > /etc/local.d/fcnet.start
#!/bin/sh
set -eu
devs=$(ip -o link show | sed -n 's/^[0-9]*: \([^:@]*\).*link\/ether 06:00:ac:.*/\1/p')
for dev in $devs; do
    mac=$(ip -o link show dev "$dev" | sed -n 's/.*link\/ether \(..:..:..:..:..:..\).*/\1/p')
    # MAC 06:00:XX:YY:ZZ:WW encodes IP X.Y.Z.W (last 4 bytes)
    b2=$(printf "%.2s" "${mac#*:*:}")
    b3=$(printf "%.2s" "${mac#*:*:*:}")
    b4=$(printf "%.2s" "${mac#*:*:*:*:}")
    b5=$(printf "%.2s" "${mac#*:*:*:*:*:}")
    guest_ip="$(printf "%d.%d.%d.%d" "0x${b2}" "0x${b3}" "0x${b4}" "0x${b5}")"
    ip addr add "${guest_ip}/24" dev "$dev"
    ip link set "$dev" up
    ip route add default via "${guest_ip%.*}.1" dev "$dev"
done
SCRIPT
chmod +x /etc/local.d/fcnet.start

echo 'hostname -F /etc/hostname' >> /etc/local.d/hostname.start
chmod +x /etc/local.d/hostname.start

cat > /etc/resolv.conf <<'DNS'
nameserver 1.1.1.1
DNS

rc-update add local default
EOR
