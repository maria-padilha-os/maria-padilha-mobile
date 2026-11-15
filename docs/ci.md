# Image CI and QEMU serial smoke test

The CI workflow has two jobs:

| Job | What it does | Privileges |
| --- | --- | --- |
| `scaffold-checks` | Runs `tests/all.sh`, config/files/secrets/checksum checks and the shell tests | none |
| `image-smoke` | Builds a minimal aarch64 rootfs, boots it under QEMU, requires a serial marker, uploads artifacts | installs QEMU with the runner's package manager; the image build itself needs no root |

`image-smoke` is intentionally **not** a release job. It does not create a
GitHub release, push an image, flash a device, partition a disk, mount a loop
device or run `pmbootstrap install`. Artifacts are ordinary workflow artifacts
with a seven-day retention period.

## What is built

The full pmbootstrap image needs `sudo`/`doas`, a chroot and mounts, and takes
far longer than a hosted-runner budget. CI therefore builds the smallest
honest bootable artifact instead:

1. Fetch the pinned Alpine aarch64 minirootfs and pinned Alpine `virt` kernel.
2. Verify both release artifacts against the SHA-256 pins in
   [`config/smoke.conf`](../config/smoke.conf) **before** unpacking.
3. Replace PID 1 with [`config/smoke/init.sh`](../config/smoke/init.sh), which
   mounts only private `proc`/`sys`/`devtmpfs`, prints
   `MARIA_PADILHA_QEMU_SMOKE_OK` (the known marker), and powers off.
4. Pack a deterministic gzip newc initramfs with
   [`scripts/smoke-cpio.py`](../scripts/smoke-cpio.py).
5. Boot it with `qemu-system-aarch64 -machine virt`, no disk, no network and no
   display, and read the marker from the serial console.

This validates the pinned kernel and aarch64 userspace boot path, not Phosh,
Squeekboard, the modem or the camera. Those remain manual QEMU checklist gates
on a full image built by a privileged builder. The full image build is still
covered by `make check` and `make build-dry-run`.

## Commands

```sh
# Unprivileged local build of the smoke rootfs.
scripts/build-smoke-rootfs.sh

# Default: use KVM only when it can accelerate this guest. Fails clearly if
# KVM is unavailable instead of silently running emulation forever.
scripts/qemu-smoke.sh

# Explicit, bounded TCG for a cross-architecture or KVM-less host.
scripts/qemu-smoke.sh --accel tcg

# Convenience targets.
make smoke       # build + auto acceleration
make smoke-tcg   # build + explicit bounded TCG
```

The smoke guest has **no block device, no NIC and no display**. `-nic none`,
`-display none` and a kernel/initramfs-only boot are part of the QEMU command,
so CI cannot flash or mount anything.

## KVM behaviour

`--accel auto` (the default) checks all of the following before starting QEMU:

- the guest architecture can run natively on the host (an aarch64 guest needs
  an aarch64 host; KVM cannot accelerate a cross-architecture guest),
- `/dev/kvm` exists and is readable/writable by the unprivileged runner,
- the installed QEMU advertises the `kvm` accelerator.

If any check fails, the helper exits immediately with a `FAIL KVM ...` message
and tells the user to pass `--accel tcg` for a bounded emulated boot. It does
not fall back silently. On a native aarch64 runner the CI step therefore
requires KVM and fails fast when the host lacks it.

Hosted x86_64 runners cannot KVM-accelerate an aarch64 guest. For that
specific case CI explicitly passes `--accel tcg`; the boot still has a hard
wall-clock timeout, so a missing or broken guest cannot hang the job. If the
project later adds a native aarch64 KVM runner, no workflow change is needed:
the `aarch64` branch already uses `--accel auto`.

## Time and size budget

These are the budgets enforced or measured by the smoke path. They are sized
for a two-core hosted runner; a builder with a warm cache should be faster.

| Item | Budget | Enforcement |
| --- | --- | --- |
| Pinned downloads (kernel + minirootfs) | 32 MiB | `SMOKE_DOWNLOAD_BUDGET_MIB`; size check before use |
| Uploaded smoke artifact (kernel + initramfs) | 32 MiB | `SMOKE_ARTIFACT_BUDGET_MIB`; build fails if exceeded |
| Rootfs build (download from warm cache, unpack, pack) | 120 s | `SMOKE_BUILD_TIME_BUDGET`; workflow `timeout-minutes: 15` |
| QEMU TCG boot to marker | 300 s | `SMOKE_BOOT_TIME_BUDGET`; hard poll timeout, QEMU is killed |
| QEMU KVM boot to marker | 60 s | `SMOKE_KVM_BOOT_TIME_BUDGET`; hard poll timeout |
| Whole `image-smoke` job including package install | 15 min | workflow `timeout-minutes` |

Current reference sizes from the pins in `config/smoke.conf`:

- kernel `vmlinuz-virt`: about 9.2 MiB (9,642,496 bytes),
- minirootfs download: about 3.8 MiB (3,971,704 bytes),
- smoke initramfs: a few MiB compressed,
- combined uploaded kernel + initramfs: well under the 32 MiB artifact budget.

`out/smoke/manifest.txt` records the exact byte counts, pins and budgets for
each run. The workflow fails before upload if the artifact budget is exceeded.

## Checksums and artifacts

`scripts/build-smoke-rootfs.sh` writes:

| Path | Purpose |
| --- | --- |
| `out/smoke/vmlinuz-virt` | pinned kernel copied into the artifact |
| `out/smoke/vmlinuz-virt.sha256` | kernel checksum |
| `out/smoke/maria-padilha-smoke-aarch64.initramfs.gz` | minimal aarch64 rootfs |
| `out/smoke/maria-padilha-smoke-aarch64.initramfs.gz.sha256` | initramfs checksum |
| `out/smoke/smoke-inputs.sha256` | checksums of smoke config, scripts and docs |
| `out/smoke/smoke-inputs.digest` | checksum of the input manifest |
| `out/smoke/manifest.txt` | pins, marker, byte counts and budgets |
| `out/smoke/qemu-smoke.log` | serial console log from the boot |
| `out/smoke/qemu-version.txt` | QEMU version used by the runner |

`scripts/qemu-smoke.sh` refuses to boot if either the kernel or initramfs
checksum file is missing or does not verify. The CI artifact includes the
kernel, initramfs, both checksums, the input manifest, the serial log and the
QEMU version, so a reviewer can reproduce the boot or compare hashes without a
release.

## Cache safety

Only the pinned downloads are cached, under `.scratch/smoke-cache`:

- the cache key includes the hash of `config/smoke.conf`, so changing a pin
  creates a new cache entry;
- a restored file is re-hashed against the pin before use;
- a cached file with the wrong hash is deleted and downloaded again;
- the cache never contains `out/`, QEMU binaries or any build artifact.

A poisoned or stale cache therefore causes a checksum failure and a clean
re-download, not an unchecked boot.

## Failure modes

| Symptom | Result |
| --- | --- |
| No `/dev/kvm` on a native host | `FAIL KVM acceleration is unavailable: ...`; exit before QEMU starts |
| Cross-architecture guest with `--accel kvm` | Clear `KVM cannot accelerate ...` failure; use `--accel tcg` or an aarch64 runner |
| No marker within the boot budget | QEMU is terminated and the serial log path is printed |
| QEMU exits before the marker | Non-zero CI failure with the exit status and serial log |
| Wrong download or restored cache | Checksum mismatch; no unpack and no boot |
| Oversized artifact | Build fails against the documented budget |
| Missing checksum file | Boot refuses an unchecked artifact |

## Boundaries

- No release publication: the workflow uploads workflow artifacts only.
- No physical-device flashing: no `pmbootstrap flasher`, `fastboot`, `dd`,
  `--disk`, loop device or `/dev/sd*`/`/dev/mmcblk*` path is used.
- No privileged image build in CI. Installing QEMU on the runner is the only
  package-manager step; the rootfs build and boot run unprivileged.
- The full pmbootstrap image remains a builder-only task because it needs
  chroot/mount privileges. Its 30-minute Phosh gate is documented in
  [`docs/build.md`](build.md) and ADR 0001; this smoke budget is deliberately
  separate and much smaller.
