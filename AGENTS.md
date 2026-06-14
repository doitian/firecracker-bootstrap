# AGENTS.md — firecracker-bootstrap

## Overview

Toolchain for provisioning and booting lightweight microVMs using [Firecracker](https://github.com/firecracker-microvm/firecracker). Automates guest kernel extraction, OCI-image-based rootfs baking, host networking setup, and single/multi-node microVM cluster launching for distributed systems testing (e.g., Jepsen/etcd).

**Remote:** `git@github.com:doitian/firecracker-bootstrap.git` (branch: `main`)

## Tech Stack

- **Shell:** `bin/*.sh` — all orchestration logic
- **Task runner:** `mise` (defined in `mise.toml`)
- **Cluster orchestration:** `process-compose` (auto-installed by mise)
- **Images:** Dockerfiles (`rootfs/*/Dockerfile`) built/pushed via GitHub Actions; Firecracker VM configs (`rootfs/*/config.json`)

There is no compiled code, no package manager, no linter, and no test framework.

## Commands

All tasks run via `mise run <task>` from repo root.

### Guest Kernel

```bash
mise run extract-kernelfs              # Pull kernel OCI image → kernelfs/<version>/
```

### Rootfs Images

```bash
mise run bake-rootfs kernelfs/6.18-fc-amd64 alpine          # Alpine ext4 rootfs
mise run bake-rootfs kernelfs/6.18-fc-amd64 debian          # Debian ext4 rootfs
mise run bake-rootfs kernelfs/6.18-fc-amd64 debian-jepsen   # Debian + Jepsen deps
ROOTFS_SIZE_MB=2048 mise run bake-rootfs ...                # Optional: override disk size (default 1024 MB)
```

### Host Networking

```bash
mise run host-network:up --count 5      # Create fc-br0 bridge, tap2..tapN, nftables NAT, UFW rules
mise run host-network:down --count 5    # Tear down
```

### Start VMs

```bash
bin/start-vm.sh alpine 0                # Launch node 0 from Alpine rootfs (serial console: root/root)
bin/start-vm.sh debian 0                # Launch node 0 from Debian rootfs
bin/start-vm.sh alpine 0 --config-only  # Print generated JSON config without booting
bin/start-vm.sh alpine 0 --set machine-config.vcpu_count=4  # Override config values
```

### Clusters

```bash
# After host-network:up:
process-compose -f clusters/jepsen-etcd/process-compose.yaml up   # 5-node etcd cluster
```

### SSH Keys & Cleanup

```bash
mise run copy-ssh-keys --count 5        # Copy SSH public key to all nodes
mise run cleanup                        # Remove all generated and runtime files (kernelfs, rootfs ext4, run)
mise run cleanup:run                    # Remove per-node runtime files (run/*)
mise run cleanup:kernelfs               # Remove extracted kernel filesystem directories (kernelfs/*)
mise run cleanup:rootfs                 # Remove baked rootfs ext4 images (rootfs/*/*.ext4)
```

## Directory Structure

```
bin/              → Executable shell scripts (start-vm, bake-rootfs, extract-kernelfs, setup-host-network, copy-ssh-keys)
kernelfs/         → Extracted guest kernel + modules (generated, gitignored)
rootfs/           → Per-distro Dockerfile + config.json + *.ext4 (ext4 is generated, gitignored)
clusters/         → process-compose.yaml definitions for multi-node clusters
run/              → Per-node writable rootfs copies + logs + generated configs (runtime only)
.github/workflows/→ CI: builds & pushes rootfs Docker images on push to main
```

## Key Scripts

| Script | Lines | Purpose |
|--------|-------|---------|
| `bin/start-vm.sh` | ~168 | Parse args, generate per-node config from template, create writable CoW rootfs copy, launch firecracker |
| `bin/bake-rootfs.sh` | ~90 | Pull OCI image via skopeo, create/mount ext4, extract rootfs layers + kernel modules |
| `bin/setup-host-network.sh` | ~195 | Create/destroy fc-br0 bridge, tap devices, nftables rules, UFW rules |
| `bin/extract-kernelfs.sh` | ~54 | Pull kernel OCI image, save layer tarballs, extract vmlinux.bin |
| `bin/copy-ssh-keys.sh` | ~77 | Copy SSH public key from ssh-agent to all nodes via sshpass |

## Node IP Convention

Node index `N` → tap device `tap$((N+2))`, IP `172.16.0.$((N+2))`. Nodes 0..4 → taps 2..6, IPs 172.16.0.2..172.16.0.6.

## CI/CD

`.github/workflows/build-rootfs.yml` builds Docker images from each `rootfs/*/Dockerfile` and pushes to `ghcr.io/doitian/firecracker-bootstrap:<tag>` on push to `main`. PRs build only, no push.

## Prerequisites

`firecracker`, `mise`, `skopeo`, `jq`, `mkfs.ext4`, `sudo`, `ip`, `nft`, `ufw`, `/dev/kvm` access.
