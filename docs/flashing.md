# Flashing and recovery

This is the safe path onto and off a Maria Padilha Mobile phone. It is a
**manual, review-first procedure**, not an installer. The repository ships a
read-only preflight ([`scripts/flash-check.sh`](../scripts/flash-check.sh)) and
this document; it does not ship a flasher, partitioner or bootloader tool.

> **Status: no physical device is supported yet.** `qemu-aarch64` is the only
> target this checkout builds. `pine64-pinephone` is a documented **bring-up
> candidate**, not a support claim. No image has been built for a phone or
> flashed from this checkout. A physical image build path is still a separate,
> reviewed task.

The decision context is [ADR 0001](adr/0001-mobile-base-and-reference-device.md);
the build path is in [Building the QEMU image](build.md). The machine-readable
matrix lives in [`config/flashing.conf`](../config/flashing.conf).

## Hard rules

1. **Never flash automatically.** No script in this repository may run a write
   command. `scripts/flash-check.sh` only reads and validates. There is no
   `--write`, `--yes` or `--force` mode, and none should be added.
2. **Only flash an image you built and verified.** Do not flash a random
   download, a partially copied file or an image whose `.sha256` is missing.
3. **Only flash a device in the matrix below.** QEMU is not a phone. Unknown
   devices are refused by the preflight.
4. **Never use an unlock exploit, leaked signing key, paid unlock service or
   test-point short.** No exceptions.
5. **Do not use a daily-driver phone.** Treat the device and its storage as
   disposable for the whole exercise.
6. **Root is only for the manual write step.** The preflight never needs it.
   Do not run privileged commands from a repository test or CI job.
7. **Stop if anything is ambiguous.** The [stop conditions](#stop-conditions)
   are part of the procedure.

## Supported-device matrix

| Device | Repository status | Flash media | Host write path | Bootloader / unlock | Recovery | Support claim |
| --- | --- | --- | --- | --- | --- | --- |
| `qemu-aarch64` | **Supported for QEMU only** (`virtual-only`) | none | never a block device; boot with `scripts/run-qemu.sh` | not applicable | re-create `out/` and boot again | a VM, not a phone; no physical support |
| `pine64-pinephone` | **Bring-up candidate, not supported** (`bring-up`) | microSD | a whole removable disk through a card reader, manual `dd` only | open FOSS U-Boot; no unlock procedure is documented or needed for the SD path | boot a known-good SD card; eMMC recovery through upstream instructions only | **no** until the physical checklist passes on a real unit |
| Other Nura phones | **Unsupported** | none | none documented here | vendor/Nura specific | upstream only | **no** |
| Phones requiring unlock exploits, leaked keys or a test-point short | **Prohibited** | none | none | out of scope | not applicable | **no** |

The matrix is intentionally short. A new row is an ADR-level decision, not a
copied command line. The PinePhone row becomes `supported` only after the
[first-boot checks](#first-boot-and-acceptance) pass on the reference unit and
the result is recorded in the repository.

`FLASH_STATUS` in `config/flashing.conf` is the machine-readable form. The
preflight prints the status and warns on every `bring-up` run. Use
`--strict-support` in release tooling to require `supported`:

```sh
scripts/flash-check.sh --device pine64-pinephone \
  --image out/maria-padilha-pine64-pinephone.img --image-only --strict-support
```

That command exits 2 today because no physical target is supported.

## Prerequisites

### Host

- Linux with `sha256sum`, `lsblk` (util-linux), `realpath`, `stat` and `awk`.
- `dd` and `sync` for the manual write, plus `cmp` for the optional read-back
  and `rsync` for the home-directory backup example.
- `ddrescue` if the source card is failing and must be imaged read-only before
  recovery work begins.
- A reliable USB card reader. The target must report `RM=1` (removable). Card
  readers that hide the removable flag are refused by the preflight; use a
  different reader rather than bypassing the check.
- Enough free space for a backup, plus a second known-good boot medium.
- The manual write needs root (`sudo`/`doas`) because it writes a raw device.
  The preflight is intentionally unprivileged and refuses to run as root.

### Phone and media

- A **spare** PinePhone-class unit with a known revision. Record the model and
  revision before starting; hardware revisions differ.
- A microSD card larger than the image. The configured image size is 2 GiB;
  allow the preflight's 16 MiB margin and normal card overhead.
- A charged phone or a stable power source. Never flash on a low battery.
- A card reader and, for recovery, a second known-good SD card.
- The upstream device page and recovery notes for the exact revision. Do not
  rely on this document for hardware-specific bootloader recovery.

### Image

- An image built by a reviewed physical build path, stored under `out/`, with
  its `.sha256` manifest. **This checkout has no physical image builder yet**;
  `scripts/build.sh` refuses `--device pine64-pinephone` by design. Until that
  path exists, there is nothing here that is safe to flash.
- The image and manifest must be on local storage, not a compressed archive,
  network share or browser download directory. Copy first, verify after copy.

### Knowledge

Read the whole document before touching a card. If you cannot explain which
`/dev` node is the card, which node is the phone and where the backup is, stop.

## Back up first: data-loss warning

> **DATA LOSS — READ THIS TWICE.** Flashing replaces the entire target. Every
> partition, operating system, application, photo, message, call log and
> encryption key on that storage is destroyed. `dd` writes to the block device
> you name; a typo such as `/dev/sda` instead of `/dev/sdb` can destroy your
> computer's disk. There is no undo. A checksum proves the image is intact, not
> that you chose the right target.

### What to back up

1. **User files:** photos, videos, documents, downloads, voice recordings and
   anything under the home directory that is not reproducible.
2. **Communications:** contacts as vCard, SMS/MMS exports, call logs and any
   chat history the app can export. Export from the app while the current OS
   still boots.
3. **Configuration and credentials:** Wi-Fi/VPN profiles, account recovery
   codes, SSH/GPG keys, password-manager export, and the disk-encryption
   passphrase or recovery key. Put secrets in a password manager, not in the
   same folder as the image.
4. **Application data:** game saves, offline maps, camera originals and any
   app-specific export.
5. **Device facts:** model, hardware revision, modem revision, bootloader
   version, IMEI (only if you need it for carrier support; store it privately),
   and the exact image name/checksum you intend to write.

### How to back up

For a running phone, copy the home directory to an external drive:

```sh
rsync -a --info=progress2 "$HOME/" /run/media/"$USER"/BACKUP/phone-home/
sync
```

Replace `/run/media/$USER/BACKUP` with the mounted backup destination. Do not
back up onto the SD card you are about to erase.

For a removable card or an accessible eMMC, an image backup preserves the
partition table and files. Power the phone off first, remove the card, and read
it through the reader:

```sh
lsblk -o NAME,SIZE,TYPE,RM,RO,TRAN,MOUNTPOINTS,MODEL
# Replace sdX with the source card, never with the backup destination.
sudo dd if=/dev/sdX of="$HOME/backups/pinephone-$(date +%F).img" \
  bs=4M status=progress conv=fsync
sync
sha256sum "$HOME/backups/pinephone-$(date +%F).img"
```

This is a read of the source. It still needs root for the raw device. If the
card is damaged, image it with `ddrescue` instead of `dd`, and work from the
image rather than the failing card.

### Verify before erasing

- Run `sha256sum` on the backup and keep the digest somewhere else.
- If the backup is a filesystem image, mount it **read-only** and open a few
  known files. (Mounting is a privileged action; this repository does not do it
  for you.)
- Confirm the encryption key or recovery phrase is available. Without it, an
  encrypted backup is not recoverable.
- Record the backup location and checksum in your notes. A backup you cannot
  find or read is not a backup.
- Only then remove the card or start the write.

## Bootloader unlocking warning

> **BOOTLOADER UNLOCK — HIGH RISK.** Unlocking a bootloader can wipe all user
> data, void the warranty, disable DRM/banking/attestation features, trip an
> anti-rollback fuse, and leave the phone unbootable if interrupted. Some
> devices can never be relocked safely. Unlocking is not required for the
> PinePhone microSD path below; if your device is not the documented reference
> class, stop.

Rules for any device that does require unlocking:

1. Use only the official vendor or upstream project procedure for the exact
   model and revision. Do not use an exploit, leaked key, paid service,
   test-point short or a procedure copied from a different model.
2. Read the procedure to the end, including the relock and recovery sections,
   before starting. Confirm that a recovery path exists for a failed unlock.
3. Back up and verify first. Unlocking commonly erases the device.
4. Do not relock a bootloader while non-stock firmware is installed. A relock
   can brick a device that would otherwise boot.
5. Keep the phone connected to stable power and do not interrupt the process.
6. If the unlock tool asks for an account, a token, a payment or a "bypass",
   stop. The repository does not support that path.

The PinePhone reference uses an open FOSS bootloader; the microSD path does not
require an unlock procedure. This document deliberately does **not** provide a
bootloader unlock, flash or recovery procedure for any other phone.

## Verify the image

Build on a disposable builder, not on the phone, and keep the output under
`out/`:

```sh
make check
# Full image build needs a builder that can authorize pmbootstrap's
# chroot/mount work. The physical target is refused in this milestone.
make build
```

Verify the manifest from the directory that contains it, because the manifest
records a basename:

```sh
(cd out && sha256sum --check --strict maria-padilha-pine64-pinephone.img.sha256)
```

The preflight repeats the check and rejects:

- a missing, empty, symlinked or non-regular image;
- an image outside `out/`;
- a missing, symlinked or multi-line manifest;
- a malformed hash or a manifest naming a different file;
- any byte-level checksum mismatch.

**A checksum is integrity, not authenticity.** This repository has no image
signing key or signature-verification path. A checksum detects corruption and
accidental substitution; it does not prove who built the image. Use an image
you built yourself or transferred over a channel you trust. Never publish a
"verified" claim based on SHA-256 alone.

## Dry-run/preflight check

The preflight is the last automated gate before a human writes anything:

```sh
scripts/flash-check.sh --help

# Validate only the image and manifest (useful in CI):
scripts/flash-check.sh --device pine64-pinephone \
  --image out/maria-padilha-pine64-pinephone.img --image-only

# Validate only a proposed target device:
scripts/flash-check.sh --device pine64-pinephone --target-only --target /dev/sdX

# Full preflight: image + target, no write:
scripts/flash-check.sh --device pine64-pinephone \
  --image out/maria-padilha-pine64-pinephone.img --target /dev/sdX
```

What the full preflight enforces:

| Check | Refusal examples |
| --- | --- |
| Device is in the matrix and not virtual/unsupported | `qemu-aarch64`, unknown names |
| Image is a real file under `out/` | symlinks, `/tmp/image.img`, archives |
| Manifest is one valid line naming this image | missing, extra lines, wrong basename |
| SHA-256 matches exactly | truncated download, edited image |
| Target is a canonical `/dev/` node | symlinks, relative paths, `/dev/disk/by-id/...` |
| Target is a block device and a whole disk | `/dev/null`, a partition such as `/dev/sda1` |
| Target is removable and not read-only | host NVMe/SATA disk, write-protected card |
| Target and all partitions are unmounted | any live mountpoint |
| Target and all partitions are not swap | active swap |
| Target is large enough for the image + margin | too-small card |
| **No write path exists** | there is no `--write`, `--yes` or `--force` |

Exit status is `0` when the requested checks pass (even for a `bring-up`
device), `1` for a safety failure, and `2` for a usage error or a failed
`--strict-support` gate. A green result is **not** a support claim and does not
authorize a write. Re-run it immediately before the manual write: the image,
manifest, mounts or target can change after the first run.

The preflight is itself tested without touching a device:

```sh
make flashing-test
```

## Manual flashing commands (microSD)

> **Do not run this against a hypothetical or unsupported image.** The current
> checkout has no physical image builder, so the command below is a future
> bring-up gate, not a supported release procedure. It is included so the full
> manual path can be reviewed before that gate is opened.

### 1. Identify the target, with all other removable media unplugged

```sh
lsblk -o NAME,SIZE,TYPE,RM,RO,TRAN,MOUNTPOINTS,MODEL
```

The target must be a **whole disk** with `TYPE=disk`, `RM=1`, `RO=0`, and no
mountpoints. Write down its size and model. `/dev/sda` is not a default; it is
whatever the card reader enumerated. If two candidates look plausible, stop and
remove one.

### 2. Run the preflight

```sh
scripts/flash-check.sh --device pine64-pinephone \
  --image out/maria-padilha-pine64-pinephone.img --target /dev/sdX
```

Replace `/dev/sdX` with the exact node you identified. Do not continue if the
model, size, transport or mount state differs from what you saw.

### 3. Unmount every partition of the target

Use the explicit partition names from `lsblk`, for example:

```sh
sudo umount /dev/sdX1
```

Do not use a wildcard or a computed path. If a partition is busy, find the
process and stop it; do not force-unmount and do not proceed while mounted.

### 4. Write the whole disk, not a partition

```sh
sudo dd if=out/maria-padilha-pine64-pinephone.img of=/dev/sdX \
  bs=4M status=progress conv=fsync
sync
```

Check the `if=` and `of=` values character by character before pressing Enter.
`of=/dev/sdX` is the whole disk; `of=/dev/sdX1` is only the first partition and
will not produce a bootable result, while a wrong whole-disk node can destroy
the host. `conv=fsync` flushes the write. If `dd` reports an error or runs out
of space, stop; do not immediately retry with a different target.

### 5. Verify the write (recommended)

Read back exactly the image length and compare it to the source:

```sh
sudo cmp -n "$(stat -c %s out/maria-padilha-pine64-pinephone.img)" \
  out/maria-padilha-pine64-pinephone.img /dev/sdX && echo "read-back matches"
```

`cmp` only reads. A mismatch means the card, reader or write was faulty; do not
boot it as if it succeeded. Re-run the write on a different card/reader before
suspecting the phone.

### 6. Re-read the partition table

Remove and reinsert the card reader, or use the read-only `lsblk` view to
confirm the new layout. If you use a privileged re-read tool such as
`blockdev --rereadpt`, that is a manual host action outside this repository.

### 7. Boot the phone

Power the phone off, insert the card, and boot. Follow the upstream boot-order
instructions for the exact PinePhone revision; if it still starts the old
system, power off, re-seat the card and confirm the boot medium. Do not
interrupt the first boot: it can take several minutes on this class of
hardware.

### Internal eMMC is not covered

Do **not** run `dd` against a PinePhone's internal eMMC from this document. The
reference bring-up path is microSD first. eMMC recovery/reinstall, JumpDrive and
bootloader repair are upstream-specific procedures and must be reviewed
separately after the QEMU and SD gates pass. A generic `dd` command is not a
substitute for those instructions.

## First boot and acceptance

A preflight pass only means the bytes and target looked safe. It is not a boot
test. Record each item on the actual unit:

| Check | Evidence to record |
| --- | --- |
| Boot medium | card model/size, reader, image checksum |
| Bootloader and kernel | visible boot progress or serial log; no unexplained reset |
| Phosh session | reaches the lock screen and unlocks |
| Touch and display | both orientations, no dead regions, readable palette |
| On-screen keyboard | Squeekboard appears, terminal/URL/PIN layouts work |
| Wi-Fi and Bluetooth | association and a real transfer |
| Audio | speaker, earpiece, microphone |
| Suspend/resume | one manual cycle, no lost session |
| Modem detection | ModemManager sees the modem, SIM state is correct |
| Calls and SMS | one real call and one real message, if a SIM is available |
| Mobile data | carrier-dependent; record success or the exact failure |
| Disk encryption | unlock works; recovery key is stored separately |
| Recovery | a known-good SD card boots after the test image is removed |

A failure is a result, not a reason to flash repeatedly. Capture logs, power
off, and return to a known-good medium.

## Recovery and unbrick notes

Recovery starts with **not making it worse**. Power off, remove the card, and
do not reflash the same way until you know what failed.

### General decision table

| Symptom | First response | Do not do |
| --- | --- | --- |
| Phone does not power on | Charge for 30 minutes with a known-good cable; check the battery switch; try a known-good boot medium | Do not open the case or short pins |
| Black screen but the phone vibrates or shows a charge LED | Remove the SD card and boot a known-good medium; capture the boot log if a console is available | Do not assume the image is at fault and rewrite the card blindly |
| Still boots the old OS | Power off, re-seat the card, verify the boot medium/order for the revision | Do not erase the old OS first |
| Boot loop after a new image | Remove the card, boot known-good media, re-verify the image checksum, reflash or try another card | Do not keep power-cycling while writing |
| Card is not detected | Try another reader/port, inspect the contacts, try a different card | Do not force the card into the slot |
| Filesystem or partition errors | Image the card with `ddrescue` before any repair; work on a copy | Do not mount read-write or run repair tools on the only copy |
| eMMC boot is broken but SD boots | Boot the known-good SD, then follow the upstream eMMC recovery path | Do not `dd` a host image to eMMC without the documented procedure |
| Bootloader appears damaged | Stop; use the official PINE64/Nura recovery documentation for the revision | Do not use an exploit, leaked tool, test-point short or unverified "unbrick" image |
| Data is inaccessible | Make a read-only image of the medium first; keep the original untouched | Do not reformat the only copy to "fix" it |

### PinePhone-specific notes

- The PinePhone reference is valued because it can boot from microSD. Keep a
  known-good card available **before** the bring-up attempt; it is the primary
  recovery medium.
- If the eMMC installation is unusable, boot the known-good card and use the
  upstream eMMC reinstall/recovery procedure. JumpDrive or an equivalent
  upstream tool may be needed; this repository does not provide or validate
  those commands.
- Allwinner-based hardware may expose a low-level recovery mode (FEL). Do not
  short test points or follow an unverified FEL recipe from a forum. Use the
  official project instructions and a serial console if one is available.
- A bootloader repair can erase the eMMC. Back up first, and treat the phone as
  data-lost if the backup was never verified.

### QEMU recovery

There is no unbrick step for a virtual target. Stop the VM, delete the bad
artifact under `out/` or `.scratch/`, re-run `make check`, rebuild, and boot
again. The QEMU target is never written to a host block device.

### When recovery is not possible here

This repository does not provide a bootloader image, a low-level flashing tool,
a signed recovery image, or a device-specific unbrick procedure. If recovery
requires any of those, the correct action is to stop and escalate to the device
maintainer with the logs, image checksum, card/reader details and the exact step
that failed.

## Stop conditions

Stop immediately, power off and report instead of "trying one more thing" if:

- the backup is missing, unverified or stored on the target you are about to
  erase;
- the target node, model, size or mount state is ambiguous;
- the device is not a row in the [matrix](#supported-device-matrix);
- the device requires a bootloader unlock, exploit, leaked key or test-point
  short;
- the image lacks a manifest, fails its checksum, or is outside `out/`;
- a command would write outside this checkout, or a step needs a privileged
  action that is not in this document;
- the preflight fails for any reason;
- the phone, card or reader behaves inconsistently, overheats or loses power.

A stopped attempt is recoverable. A guessed `dd` is not.

## References

- [ADR 0001: Mobile base and reference device](adr/0001-mobile-base-and-reference-device.md)
- [Building the QEMU image](build.md)
- [QEMU telephony checklist](qemu-telephony-checklist.md)
- [QEMU camera checklist](qemu-camera-checklist.md)
- Nura install and device pages:
  <https://nura.eco/install/> and
  <https://wiki.nura.eco/wiki/PINE64_PinePhone_(pine64-pinephone)>
- PINE64 PinePhone hardware and recovery wiki:
  <https://wiki.pine64.org/wiki/PinePhone>

Upstream pages and hardware revisions change. Re-check the exact device page
immediately before a physical bring-up; do not treat a link here as a validated
procedure for your unit.
