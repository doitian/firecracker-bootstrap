FROM ghcr.io/doitian/firecracker-bootstrap:debian

RUN /bin/bash <<'EOR'
set -euo pipefail

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends sudo
apt-get clean
rm -rf /var/lib/apt/lists/*
EOR
