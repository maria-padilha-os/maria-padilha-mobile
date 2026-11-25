# QEMU release-candidate evidence

This page records the QEMU-only candidate built from this checkout. **The
validated target is `qemu-aarch64`, not physical hardware.** No phone image was
flashed, installed, uploaded or published. The candidate is an unprivileged
kernel + initramfs boot artifact, not the full Phosh image.

The full `pmbootstrap` image (`out/maria-padilha-qemu-aarch64.img`) was **not**
built in this run. Its builder path needs `sudo`/`doas` for chroot and mount
operations, which this run was not allowed to invoke. The full Phosh display
session and every manual QEMU/hardware checklist therefore remain unvalidated.

## Candidate artifacts

Built on 2026-11-25 by `scripts/build-smoke-rootfs.sh` from the pins in
[`config/smoke.conf`](../config/smoke.conf).

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Kernel | `out/smoke/vmlinuz-virt` | 9,642,496 | `ebf299aa6829b15166008db24b076ac0a8b3e778c72ed66be488742aaf05d741` |
| Initramfs image | `out/smoke/maria-padilha-smoke-aarch64.initramfs.gz` | 3,966,495 | `c400e329487020ab96cdbc270bb3a50681f1688fd948a740ebb18f893b241193` |
| Combined boot image | kernel + initramfs | 13,608,991 | see the two rows above |

Supporting evidence in `out/smoke/`:

| File | SHA-256 |
| --- | --- |
| `manifest.txt` | `95ca645490a7f7854d422e66586832afcdf04a6946e54757cc02c0f8d1c4f111` |
| `smoke-inputs.sha256` | `91c79f2496cfefa4d6d591d41f6835a608cfcb5a7f11928cb5c6dcea0f6bb993` |
| `smoke-inputs.digest` | `eba1a7559aaca7fadf2257d8f88fb388f6d8ed9970ce9fb2f7c69df5ed62329d` |
| `qemu-smoke.log` | `f1252c68eaefed89668d9fbeefe9721f77f117f201eba3777a6d4d39e0105f68` |
| `qemu-version.txt` | `4d3f6aed38d7ef3fdadbf8d5fe081e9ff0e88fd9e7faa3f3d65025103380d84c` |

`out/` is ignored by Git, so these files are local evidence rather than tracked
release assets. The kernel and initramfs checksums are also written next to
each artifact.

## Build inputs

Repository base commit: `44f4d1180c1a245f95389ade0138462d8039f69c` (the release
evidence and test-isolation change in this branch are applied on top of it).
The exact file-level build inputs are the eleven entries in
`out/smoke/smoke-inputs.sha256`; their manifest digest is
`eba1a7559aaca7fadf2257d8f88fb388f6d8ed9970ce9fb2f7c69df5ed62329d`.
The entries cover `config/build.conf`, `config/smoke.conf`,
`config/smoke/init.sh`, `devices/qemu-aarch64/device.conf`, the smoke scripts,
the Makefile, the CI workflow, `docs/ci.md` and `README.md`.

Pinned upstream and guest inputs:

| Input | Pin |
| --- | --- |
| Release line / target | Nura `v26.06` stable, `qemu-aarch64` (full image target) |
| `pmbootstrap` (full builder, not run) | `2.3.1`, commit `92524002926401bbe5370e27f36cd2f8a82e2e1a` |
| `pmaports` (full builder, not run) | commit `817ed870e92a64963d926354fb74c75090811fcc` |
| Alpine guest | `3.22.8`, aarch64 |
| Kernel | `6.12.115-0-virt`, pinned by SHA-256 `ebf299aa…d741` |
| Minirootfs | `alpine-minirootfs-3.22.8-aarch64.tar.gz`, pinned by SHA-256 `36091efa…bca4` |
| Boot marker | `MARIA_PADILHA_QEMU_SMOKE_OK` |

Host and QEMU:

- Host: Manjaro Linux, `x86_64`, no `/dev/kvm`, so the aarch64 guest used
  explicit TCG (`-accel tcg,thread=multi`).
- QEMU: `qemu-system-aarch64` 11.1.3, from the host package
  `qemu-system-aarch64-11.1.3-1-x86_64.pkg.tar.zst`
  (`bd50be6843e6581035f24c63f01c9e6bf50ee65badf6df7e1cba86e957898cc0`).
  The package was extracted under the ignored `.scratch/qemu-toolchain/`
  because this run could not install host packages; QEMU 8.0+ remains the
  documented host prerequisite.

## Reproducibility

The build was run twice, first into `out/smoke` and then into
`out/smoke-repro`. The kernel, initramfs, `manifest.txt`,
`smoke-inputs.sha256` and `smoke-inputs.digest` were byte-for-byte identical
across both output directories. The initramfs hash above was therefore
reproduced from the same pinned inputs in the same checkout.

The initramfs is deterministic by construction: `scripts/smoke-cpio.py` sorts
entries, fixes ownership and mtimes, and writes gzip without a filename or
timestamp. Cache hits are re-hashed against the pins before use.

## QEMU boot result

Command (the explicit TCG option is required on this x86_64 host; no KVM was
available):

```sh
PADILHA_SMOKE_QEMU_BINARY="$PWD/.scratch/qemu-toolchain/root/usr/bin/qemu-system-aarch64" \
  scripts/qemu-smoke.sh --accel tcg
```

Result: exit 0, serial marker observed after 2 seconds against a 300-second hard
budget. The guest printed:

```text
MARIA_PADILHA_QEMU_SMOKE_OK
MARIA_PADILHA_SMOKE_ARCH=aarch64
MARIA_PADILHA_SMOKE_KERNEL=6.12.115-0-virt
MARIA_PADILHA_SMOKE_PID1=1
[    1.602283] reboot: Power down
```

The full serial log is `out/smoke/qemu-smoke.log` (SHA-256 above). QEMU was
started with `-display none`, `-nic none`, `-monitor none`, no disk and no
network interface. This proves the pinned aarch64 kernel, the Alpine userspace
and the smoke PID 1 boot path. It does **not** prove a Phosh or any graphical
session.

## Test result

`bash tests/all.sh` passed (exit 0) with the candidate tree. This includes the
config/checksum gate, keyboard, power, modem, settings, camera, flashing, image
smoke-contract and shell checks, including offscreen renders of the shell
surfaces at both reference resolutions. Those offscreen renders are Qt test
renders outside QEMU, not a QEMU display or Phosh result.

`tests/shell.sh` now points `XDG_CACHE_HOME` at its private temporary directory.
This prevents a stale per-user Quickshell/QML cache from a different Qt patch
level from making later inline-keyboard renders fail with a Qt private-ABI
symbol error; it does not relax any render or image assertion.

## What remains unvalidated

Not run because the full builder needs privileged chroot/mount operations:

- `scripts/build.sh` / `pmbootstrap install` and the full
  `out/maria-padilha-qemu-aarch64.img`;
- booting that full image into Phosh, including the QEMU display/GTK path;
- the manual QEMU keyboard, power, telephony and camera checklists on the full
  image: [`qemu-keyboard-checklist.md`](qemu-keyboard-checklist.md),
  [`qemu-power-checklist.md`](qemu-power-checklist.md),
  [`qemu-telephony-checklist.md`](qemu-telephony-checklist.md),
  [`qemu-camera-checklist.md`](qemu-camera-checklist.md);
- the manual accessibility session in [`accessibility.md`](accessibility.md).

Hardware-only checks that cannot be satisfied by any QEMU result:

- flashing, first boot and recovery on a PinePhone-class device
  ([`flashing.md`](flashing.md));
- real modem registration, calls, SMS, call audio, emergency calls and SIM
  unlock ([`modem.md`](modem.md));
- a real camera sensor and portal capture ([`camera.md`](camera.md),
  [`camera-supported-devices.md`](camera-supported-devices.md));
- battery, charge-threshold, thermal and suspend behaviour on real hardware
  ([`power.md`](power.md));
- physical touch, panel, rotation, screen reader and physical-keyboard checks
  ([`accessibility.md`](accessibility.md)).

## Boundary

This is candidate evidence for the QEMU reference target only. It is not a
phone image, not a published release, and not a claim that Maria Padilha Mobile
works on physical hardware. No device was flashed, installed, mounted or
otherwise modified.
