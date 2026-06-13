# Firecracker Bootstrap

<https://labs.iximiuz.com/courses/firecracker-hands-on/run-first-microvm>

## Gotchas

- Install OpenRC. Containers don't need an init manager (since they are just
processes in the host's process tree), but a VM needs some userspace process to
become the PID 1 once the kernel finishes booting.
- Start a `getty` on the serial console (`ttyS0`) to allow logging in once the
microVM is booted. The `alpine:3` container image disables it by default in
`/etc/inittab` because containers don't need a serial console.
- Attempting to reboot the microVM will cause the firecracker process on the host to exit:

## Firecracker Config

Here is what our simplified `boot_args` string means:

- `reboot=k` shut down the guest on reboot (because Firecracker doesn't support rebooting)
- `panic=1` on panic, reboot (hence, shut down) the guest after 1 second
- `console=ttyS0` send the kernel's console I/O to the first serial port (`ttyS0`)
