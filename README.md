# Firecracker Bootstrap

## Prerequisites

- [Firecracker](https://github.com/firecracker-microvm/firecracker) on your `PATH` (override with `FIRECRACKER_BIN`)
- [mise](https://mise.jdx.dev/) to run the tasks below (it also installs `process-compose`)
- `buildah`, `jq`, `mkfs.ext4`, and `sudo` for building and baking rootfs images (`skopeo` is used as a fallback for pulling pre-built images)
- `ip`, `nft`, and `ufw` for host networking
- KVM access (`/dev/kvm`)

## Usage

All tasks are defined in `mise.toml` and run from the repo root.

### 1. Extract the guest kernel

Pulls the kernel OCI image and writes `kernelfs/6.18-fc-amd64/vmlinux.bin`:

```sh
mise run extract-kernelfs
```

### 2. Build rootfs images (optional — local build)

Build rootfs Docker images locally with `buildah`. This is the preferred approach; if you skip it, `bake-rootfs` falls back to pulling pre-built images from the registry.

```sh
mise run build-rootfs alpine          # build a single image
mise run build-rootfs                 # build all images
```

### 3. Bake a rootfs image

Creates a bootable ext4 rootfs from a Docker image tag (`alpine`, `debian`, or `debian-jepsen`) plus the extracted kernel modules. Prefers locally-built `buildah` images; falls back to pulling from `ghcr.io` via `skopeo`. The result lands at `rootfs/<tag>/<tag>.ext4`.

```sh
mise run bake-rootfs kernelfs/6.18-fc-amd64 alpine
```

Override the disk size (default 1024 MB) with `ROOTFS_SIZE_MB`:

```sh
ROOTFS_SIZE_MB=2048 mise run bake-rootfs kernelfs/6.18-fc-amd64 debian
```

### 4. Set up host networking

Creates the `fc-br0` bridge, tap devices, NAT, and firewall rules. Guests get IPs `172.16.0.2`, `172.16.0.3`, … (one per tap). Use `--count` to provision more than one tap:

```sh
mise run host-network:up --count 5
```

Tear it down when finished:

```sh
mise run host-network:down --count 5
```

### 5. Start a microVM

Launch a VM from a baked rootfs tag. The second argument is a node index starting at `0`, which maps to IP `172.16.0.<2+index>` and tap `tap<2+index>`. Each node boots from its own writable copy of the base image under `run/`.

```sh
bin/start-vm.sh alpine 0
```

Log in on the serial console with `root` / `root`, or SSH to the guest IP.

Useful options:

- `--config-only` prints the generated Firecracker config without booting.
- `--set KEY=VALUE` overrides any config value via a jq path, repeatable:

```sh
bin/start-vm.sh alpine 0 --set machine-config.vcpu_count=4
```

### Run a cluster

`clusters/<name>/process-compose.yaml` defines multi-node clusters launched with `process-compose`. For example, the 5-node Jepsen etcd cluster (set up the network with `--count 5` first):

```sh
process-compose -f clusters/jepsen-etcd/process-compose.yaml up
```

### Clean up

```sh
mise run cleanup            # remove all generated and runtime files (kernelfs, rootfs ext4, run)
mise run cleanup:kernelfs   # remove extracted kernel filesystem directories (kernelfs/*)
mise run cleanup:rootfs     # remove baked rootfs ext4 images (rootfs/*/*.ext4)
mise run cleanup:run        # remove per-node runtime files (run/*)
```

## Credit

The repo is based on <https://labs.iximiuz.com/courses/firecracker-hands-on/run-first-microvm>.

### Gotchas

- Install OpenRC. Containers don't need an init manager (since they are just
processes in the host's process tree), but a VM needs some userspace process to
become the PID 1 once the kernel finishes booting.
- Start a `getty` on the serial console (`ttyS0`) to allow logging in once the
microVM is booted. The `alpine:3` container image disables it by default in
`/etc/inittab` because containers don't need a serial console.
- Attempting to reboot the microVM will cause the firecracker process on the host to exit:

### Firecracker Config

Here is what our simplified `boot_args` string means:

- `reboot=k` shut down the guest on reboot (because Firecracker doesn't support rebooting)
- `panic=1` on panic, reboot (hence, shut down) the guest after 1 second
- `console=ttyS0` send the kernel's console I/O to the first serial port (`ttyS0`)
