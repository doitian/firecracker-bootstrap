FROM debian:bookworm-slim

RUN /bin/bash <<'EOR'
set -euo pipefail

apt-get update
apt-get install -y --no-install-recommends \
  openssh-server \
  iproute2 \
  systemd-sysv
apt-get clean
rm -rf /var/lib/apt/lists/*

sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

echo "root:root" | chpasswd

ssh-keygen -A

ln -sf /usr/lib/systemd/systemd /sbin/init

mkdir -p /etc/systemd/system/getty.target.wants /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/serial-getty@.service /etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service
ln -sf /usr/lib/systemd/system/ssh.service /etc/systemd/system/multi-user.target.wants/ssh.service

cat <<'SCRIPT' > /usr/local/sbin/fcnet-setup.sh
#!/bin/bash
set -eu
devs=$(ip -o link show | sed -n 's/^[0-9]*: \([^:@]*\).*link\/ether 06:00:ac:.*/\1/p')
for dev in $devs; do
    mac=$(ip -o link show dev "$dev" | sed -n 's/.*link\/ether \(..:..:..:..:..:..\).*/\1/p')
    b2=$(printf "%.2s" "${mac#*:*:}")
    b3=$(printf "%.2s" "${mac#*:*:*:}")
    b4=$(printf "%.2s" "${mac#*:*:*:*:}")
    b5=$(printf "%.2s" "${mac#*:*:*:*:*:}")
    guest_ip="$(printf "%d.%d.%d.%d" "0x${b2}" "0x${b3}" "0x${b4}" "0x${b5}")"
    ip addr add "${guest_ip}/24" dev "$dev"
    ip link set "$dev" up
    ip route add default via "${guest_ip%.*}.1" dev "$dev"
done
echo "nameserver 1.1.1.1" > /etc/resolv.conf
SCRIPT
chmod +x /usr/local/sbin/fcnet-setup.sh

cat <<'UNIT' > /etc/systemd/system/fcnet.service
[Unit]
Description=Firecracker network setup
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/fcnet-setup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

ln -sf /etc/systemd/system/fcnet.service /etc/systemd/system/multi-user.target.wants/fcnet.service

cat <<'UNIT' > /etc/systemd/system/fc-hostname.service
[Unit]
Description=Set hostname from /etc/hostname
Before=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'hostname -F /etc/hostname'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

ln -sf /etc/systemd/system/fc-hostname.service /etc/systemd/system/multi-user.target.wants/fc-hostname.service
ln -sf /dev/null /etc/systemd/system/networking.service 2>/dev/null || true
EOR
