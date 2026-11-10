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

QEMU normally exposes no phone battery or charger, so the power diagnostic
reports an AC-only guest with a no-battery warning. That is expected. Use the
sysfs fixtures in `tests/power.sh` for battery/charge-threshold checks and the
[manual QEMU power checklist](../../docs/qemu-power-checklist.md) for the
suspend/resume gate. Do not run the suspend step on the host laptop.

QEMU also normally exposes no cellular modem. The calls and SMS surfaces must
render the no-modem state, which `tests/shell.sh` checks offscreen and
`tests/modem.sh` checks against a real ModemManager daemon on a private session
bus. A passed-through USB modem or the emulated ModemManager D-Bus service can
exercise the call/SMS state machine, but neither is a physical-modem or
call-audio result. See [`docs/modem.md`](../../docs/modem.md) and the
[manual telephony checklist](../../docs/qemu-telephony-checklist.md).
