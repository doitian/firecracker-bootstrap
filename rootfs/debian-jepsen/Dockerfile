FROM ghcr.io/doitian/firecracker-bootstrap:debian

RUN /bin/bash <<'EOR'
set -euo pipefail

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  sudo \
  ca-certificates \
  man-db \
  curl \
  iputils-ping \
  logrotate \
  tcpdump \
  apt-transport-https \
  ntpsec-ntpdate \
  rsyslog \
  psmisc \
  faketime \
  build-essential \
  netcat-openbsd \
  vim \
  unzip \
  apt-utils \
  bzip2 \
  wget \
  iptables \
  dirmngr
apt-get clean
rm -rf /var/lib/apt/lists/*
EOR
