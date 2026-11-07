# qemu-aarch64

The first-class build target from ADR 0001. It is a Nura `community` virtual
device with a close-to-mainline aarch64 kernel, so it exercises the same
device/UI path as the physical reference without requiring a phone.

| Setting | Value |
| --- | --- |
| Arch | aarch64 |
| Kernel | stable |
| UI | Phosh |
| Init | systemd |
| Image | `out/maria-padilha-qemu-aarch64.img` |
| Memory | 1024 MiB |
| Display | headless by default; `PADILHA_QEMU_DISPLAY=gtk` for a window |

Build and boot:

```sh
scripts/build.sh
scripts/run-qemu.sh
```

The target is deliberately not `qemu-amd64`: a different architecture would
not qualify an ARM64 phone image.
