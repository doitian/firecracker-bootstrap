FROM alpine:3

RUN <<EOR
set -euo pipefail

apk add --update-cache openrc
rm -rf /var/cache/apk/*

sed -i '/^#ttyS0::respawn:/s/^#//' /etc/inittab

echo "root:root" | chpasswd

cat <<'SCRIPT' > /etc/local.d/fcnet.start
#!/usr/bin/env bash
devs=$(ls /sys/class/net | grep -v lo)
for dev in $devs; do
    mac_ip=$(ip link show dev $dev \
        | grep link/ether \
        | grep -Po "(?<=06:00:)([0-9a-f]{2}:?){4}"
    )
    ip=$(printf "%d.%d.%d.%d" $(echo "0x${mac_ip}" | sed "s/:/ 0x/g"))
    ip addr add "$ip/30" dev $dev
    ip link set $dev up
done
SCRIPT
chmod +x /etc/local.d/fcnet.start

echo 'hostname -F /etc/hostname' >> /etc/local.d/hostname.start
chmod +x /etc/local.d/hostname.start

rc-update add local default
EOR
