FROM alpine:3

RUN <<EOR
set -euo pipefail

apk add --update-cache openrc
rm -rf /var/cache/apk/*

sed -i '/^#ttyS0::respawn:/s/^#//' /etc/inittab

echo "root:root" | chpasswd

echo 'hostname -F /etc/hostname' >> /etc/local.d/hostname.start
chmod +x /etc/local.d/hostname.start

rc-update add local default
EOR
