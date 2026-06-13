FROM ghcr.io/doitian/firecracker-bootstrap:bare-bones

RUN <<EOR
set -euo pipefail

apk add --update-cache openssh
rm -rf /var/cache/apk/*

sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

ssh-keygen -A

rc-update add sshd default
EOR
