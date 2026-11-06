# ADR 0001: Mobile base and reference device

- **Status:** Accepted
- **Date:** 2026-11-06
- **Decision owner:** Maria Padilha Mobile maintainers
- **Related:** [README](../../README.md),
  [Maria Padilha DE](https://github.com/maria-padilha-os/maria-padilha-de)

## Context

Maria Padilha Mobile is the touch-first mobile OS and shell image. It shares
the Padilha palette, wallpaper language, and design tokens with the desktop,
but it is not the desktop session squeezed onto a phone.

Before writing an image builder, this ADR decides what the product is built
on. The comparison must cover package availability, kernel and firmware
support, maintenance effort, touch-stack maturity, and reuse of the existing
Padilha palette and shell work. Android is not assumed, and no hardware
support is claimed without an upstream source. "M1" below means the first
milestone: a reproducible QEMU image followed by a physical bring-up.

Terminology: postmarketOS was renamed **Nura** on 2026-09-27. This ADR uses
"postmarketOS/Nura" for the project, and keeps upstream identifiers such as
`postmarketos-ui-phosh`, `pmbootstrap`, and `pmaports`. Upstream documentation
is the source of the hardware status below; no device was flashed or booted
for this ADR.

## Decision

1. **Base:** postmarketOS (Alpine), now Nura, on the **stable** channel. Pin
   the exact release (currently v26.06) and the exact `pmaports` commit at
   image-build time. Edge is a separate development channel, not the product
   channel.
2. **Interface:** **Phosh**, with a thin Padilha layer (palette, wallpaper,
   typography, icons, sounds) rather than a shell fork in the first milestone.
3. **QEMU reference:** **`qemu-aarch64`**. It is the ARM64 virtual target and
   matches the physical reference architecture.
4. **Physical reference class:** **PinePhone-class close-to-mainline aarch64
   handsets**, represented by the PINE64 PinePhone (`pine64-pinephone`).
5. **Build approach:** wrap and pin `pmbootstrap` plus `pmaports`; do not
   write a from-scratch partitioner, bootloader installer, or image builder in
   the next task. A Padilha overlay package carries themes and assets.
6. **Init system:** systemd. Phosh supports systemd and OpenRC; M1 uses
   systemd to match the desktop and avoid a second init path if Plasma Mobile
   is revisited. If PinePhone memory measurements require OpenRC, that
   fallback is supported for Phosh but would require a separate systemd image
   for Plasma Mobile.
7. **Android:** not the base, not a fallback, and not a runtime dependency.
   No Android userspace is assumed. Some non-reference devices need vendor
   firmware; the PinePhone reference does not require an Android userspace.

## Options considered

Four combinations were evaluated:

- **A. Arch Linux ARM + Phosh**
- **B. Arch Linux ARM + Plasma Mobile**
- **C. postmarketOS/Nura + Phosh**
- **D. postmarketOS/Nura + Plasma Mobile**

A fifth option, continuing the Hyprland + Quickshell desktop shell directly on
a phone, was rejected. It is not a phone shell: it has no telephony, modem,
adaptive lock, proximity, or suspend integration, and it would require
building those pieces plus a mobile compositor before the first image. That is
a larger project than the mobile shell itself.

### Comparison summary

Scores are 1 (absent) to 5 (first-class). Weights are judgment calls, not
measurements: kernel/firmware 30%, maintenance 25%, touch maturity 20%,
package availability 15%, palette/shell reuse 10%. Hardware enablement is
weighted highest because it is the hard part of a phone OS and the part the
project cannot invent cheaply. The touch score rates the interface stack, not
device integration; integration is captured by kernel/firmware and
maintenance. The Phosh rows therefore share the same touch score, and the
Plasma rows share theirs.

| Option | Packages | Kernel | Maint. | Touch | Reuse |
| --- | --- | --- | --- | --- | --- |
| A. Arch Linux ARM + Phosh | 5 | 2 | 2 | 4 | 3 |
| B. Arch Linux ARM + Plasma Mobile | 5 | 2 | 2 | 3 | 4 |
| C. postmarketOS/Nura + Phosh | 4 | 4 | 4 | 4 | 3 |
| D. postmarketOS/Nura + Plasma Mobile | 4 | 4 | 3 | 3 | 4 |

Weighted result:

| Option | Weighted score | Verdict |
| --- | --- | --- |
| A. Arch Linux ARM + Phosh | 2.95 | Reject |
| B. Arch Linux ARM + Plasma Mobile | 2.85 | Reject |
| C. postmarketOS/Nura + Phosh | 3.90 | **Choose** |
| D. postmarketOS/Nura + Plasma Mobile | 3.55 | Fallback |

### Package availability

**Arch Linux ARM (A, B).** Arch Linux ARM is a full aarch64 rebuild of Arch,
not a separate derivative. At the time of writing, Phosh 0.57.0-2 and Plasma
Mobile 6.8.2-1 are in the `extra` repository for aarch64, so the interfaces
themselves are available. The AUR is source-based and is not an official ARM
binary repository, and building large desktop packages on a phone is
expensive. More importantly, the Arch Linux ARM platform list contains
development boards, Chromebooks, and generic aarch64, but **no phone
platform** and no phone-specific device packages for kernels, firmware,
modems, or bootloaders.

**postmarketOS/Nura (C, D).** Alpine's `apk` repositories plus `pmaports`
provide the mobile-specific layer: `postmarketos-ui-phosh`,
`postmarketos-ui-plasma-mobile`, per-device kernel packages, firmware
packages, and device codenames that `pmbootstrap` understands. The
general-purpose package set is not Arch's, so some desktop packages will be
missing or need packaging, but the packages needed to make a phone work are
first-class rather than assembled by hand.

**Verdict:** Arch wins on raw package breadth; postmarketOS/Nura wins on the
packages that matter for a phone. The difference that decides this criterion
is not the UI package, which both have, but the device and firmware stack.

### Kernel and firmware support

**Arch Linux ARM (A, B).** The generic aarch64 tarball ships `linux-aarch64`
with mainline device trees, so a mainline-supported phone can sometimes boot.
That is not the same as being supported: there is no phone device page, no
per-device kernel or firmware package, and no tested bootloader path. The
maintainer owns the port, the modem quirks, the panel and touch configuration,
and the firmware licensing. The community DanctNIX/Arch Mobile project fills
this gap for PinePhone, PinePhone Pro, and PineTab, but it is a narrow,
separate layer, not Arch Linux ARM's supported phone platform.

**postmarketOS/Nura (C, D).** Nura lists 430 device ports: 0 in `main`, 133
in `community`, 260 in `testing`, and 37 in `downstream` at the time of
writing. For this ADR, only `community` and `testing` ports with
close-to-mainline kernels count as candidate support; `downstream` is
excluded. Device packages carry the kernel and firmware, and the project
prefers close-to-mainline kernels. This is strong, but it is not a blanket
guarantee: `main` is empty, so `community` is the highest vetted tier;
`testing` is populated but is not yet a support promise. The Nura wiki also
states that Phosh does not work on downstream kernels because they lack the
required DRM support; Plasma Mobile can software-render but performs poorly.

**Verdict:** postmarketOS/Nura, clearly. The remaining risk is device-level,
which is why the reference class is a documented `community`
close-to-mainline device rather than "any aarch64 phone".

### Maintenance effort

**Arch Linux ARM (A, B).** Arch is rolling by design. There are no stable
snapshots, so a `pacman -Syu` can move the kernel, the UI, and the graphics
stack together. On a phone the maintainer also owns the bootloader, kernel,
firmware, mobile session, and image build. There is no upstream mobile QA or
device regression testing to inherit. A third-party Arch Mobile layer reduces
some of that work but adds another dependency and maintainer to track.

**postmarketOS/Nura (C, D).** Nura publishes stable releases (v26.06) and an
edge channel, and `pmbootstrap`/`pmaports` already implement image creation,
partitioning, bootloader setup, and device selection. Device maintainers carry
the kernel and firmware plumbing. The project is still a small community with
regressions and incomplete features, so pinning stable plus a `pmaports`
commit is required. But the project inherits the phone-specific plumbing
instead of rebuilding it.

**Verdict:** postmarketOS/Nura. Arch's rolling model is a strength on a
workstation and a liability on a phone that the same small team must keep
bootable.

### Touch stack maturity

**Phosh (A, C).** Phosh is a GTK3 phone shell on Phoc/wlroots. It ships the
touch pieces a phone needs: an on-screen keyboard (Stevia by default in recent
Nura releases), feedbackd for haptics and LEDs, `xdg-desktop-portal-phosh`,
and GNOME session integration. It supports both OpenRC and systemd. The GTK4
port is in progress, so the stack is still moving, but the 0.5x releases are
active and the shell has years of phone use behind it.

**Plasma Mobile (B, D).** Plasma Mobile is a Qt 6/KWin phone shell. It is
capable and more configurable, and its Qt/QML stack is closer to the desktop
Padilha shell. It requires systemd on Nura; because M1 already uses systemd,
that requirement is not an extra cost for this decision. Its real costs are
memory, the KWin/Plasma workspace integration surface, and the extra KDE
configuration to own. That is a reasonable trade for a Qt-first product, but
it is more integration surface for the first image.

**Verdict:** Phosh is the lower-risk touch stack; Plasma Mobile is viable but
costs memory and more integration work, not an extra init system. Both are
available on both bases; only postmarketOS/Nura also supplies the device-level
integration around them.

### Reuse of Maria Padilha palette and shell work

The desktop is Hyprland + Quickshell (Qt 6/QML). Its theme engine scores a
wallpaper into a Material You palette and writes GTK 3/4, Qt/Kvantum, terminal,
and application configurations. That split matters:

- **Palette, tokens, wallpaper language, typography, icons:** high reuse on
  either interface. The generator already targets GTK and Qt, so Phosh can
  consume the GTK output and Plasma Mobile can consume the Qt output. The
  mobile work is adaptation: 720x1440 crops, touch-scale spacing, and a
  mobile type ramp.
- **Shell code:** low reuse on Phosh. Quickshell QML cannot be dropped into a
  GTK3 shell, and Hyprland-specific pieces (`hyprlock`, `hypridle`) do not
  apply. Plasma Mobile is Qt/QML, so some components could be adapted, but
  Plasma's shell is a Plasma plugin, not a Quickshell session; this is a port,
  not reuse. Neither option gives a drop-in shell.

**Verdict:** the durable shared asset is the palette and design-token
pipeline, not the Quickshell code. Phosh scores medium (palette high, shell
low); Plasma Mobile scores good (palette high, some QML adaptation possible).
That difference is not large enough to outweigh Phosh's maturity and lower
integration cost for the first image. If shell-code reuse becomes a hard
requirement later, Plasma Mobile is the documented fallback.

### Why not Arch Linux ARM

Arch Linux ARM is an excellent general ARM distribution. It is not a phone
distribution: it has no phone platforms, no phone-specific device firmware
packages, and no mobile QA. Choosing it would mean building and maintaining
the device layer that postmarketOS/Nura already provides, for no compensating
advantage beyond package breadth. Package breadth does not boot a modem.

The only credible phone variant is Arch Linux ARM + DanctNIX/Arch Mobile. It
packages PinePhone, PinePhone Pro, and PineTab kernels and firmware, so it
raises Arch's kernel score for that one device family. It is still a separate,
small-maintainer layer with no stable release channel, a narrow device list,
and its own cadence. Even if it lifted A/B's kernel score from 2 to 3, their
weighted totals would be about 3.25 and 3.15, still below C at 3.90; the
project would also inherit two layers instead of one. Reject it for M1 and
revisit only if Arch becomes a hard requirement.

### Why Phosh rather than Plasma Mobile

Plasma Mobile is the better fit if the mobile shell must be Qt/QML. It is not
the better fit for the first milestone: it uses more memory on a 2-3 GB
reference device and adds KWin/Plasma integration surface. Its systemd
requirement is already covered by the M1 init choice, so init is not the
differentiator. Phosh is mature, lighter, and already used on the PinePhone.
The Padilha palette layer can target GTK without committing to a GTK shell
fork.

This is a reversible decision. The trigger to revisit is a demonstrated need
for Qt/QML component reuse that Phosh cannot satisfy, not a preference for
Qt.

## Reference targets

### QEMU: `qemu-aarch64`

`qemu-aarch64` is a Nura `community` device with a close-to-mainline kernel.
The upstream wiki documents working graphical output, keyboard and mouse,
audio, and full-disk encryption. It is the QEMU target because it matches the
physical reference architecture (aarch64) and exercises the same device and
kernel selection path as the phone. CPU emulation is slow; it is a boot and UI
target, not a performance benchmark.

The future image builder should use this device codename with Phosh. The
expected upstream flow, not run in this task, is:

```sh
pmbootstrap init          # device: qemu-aarch64, UI: phosh
pmbootstrap install
pmbootstrap qemu --image-size=2G
```

`qemu-amd64` is explicitly **not** the reference target. It is faster on an
x86_64 host and useful for quick UI smoke tests, but it uses a different
architecture and firmware/boot assumptions, so it cannot qualify an ARM64
phone image.

### Physical: PinePhone-class

The reference class is a **close-to-mainline aarch64 handset with working
DRM/GPU, 2-3 GB RAM, a 720x1440-class display, a FOSS bootloader, and no
Android userspace requirement**. The PINE64 PinePhone is the concrete
exemplar:

- `pine64-pinephone`, Allwinner A64, aarch64, 2/3 GB RAM, Mali-400 MP2.
- Nura `community`, close-to-mainline kernel. The install page lists a stable
  v26.06 image, while the device page still says "no pre-built images"; its
  device-package link also points at `device/testing` despite the `community`
  label. Verify the category and package path before relying on either (see
  risks).
- Upstream feature table: screen, touch, 3D acceleration, audio, Wi-Fi,
  Bluetooth, GPS, calls, SMS, mobile data, and FDE work; camera is partial,
  the front camera has no mainline driver, HDMI is partial, the magnetometer
  is partial, and USB OTG is broken on hardware revisions 1.0 and 1.1.

These are upstream claims, not results from this repository. They are enough
to justify a reference device for shell, touch, palette, audio, and network
work. They are not a claim that the PinePhone is a daily driver or that every
feature works on every revision.

Why this class: it is the cleanest close-to-mainline-kernel, no-Android path;
it avoids a vendor Android kernel and bootloader-unlock work; it is widely
available second-hand; and it is representative of the low-end devices the
project should remain usable on. It still loads vendor firmware blobs for
Wi-Fi/Bluetooth and the modem, so firmware licensing is not eliminated. Its
limits are real: it is slow, has little RAM, and its camera is weak. It is a
bring-up reference, not a performance target.

The physical gate is a future task. No device was purchased, flashed, or
booted here. A device is not "supported" until an image boots from SD, Phosh
starts, and the touch, OSK, Wi-Fi, audio, suspend/resume, modem detection,
calls, SMS, mobile data (carrier-dependent), FDE, and recovery checks pass on
that unit.

### Deferred: SDM845-class phones

The OnePlus 6/6T, Pocophone F1, and similar SDM845 devices are Nura
`community`, mainline, and have stable images. They are much faster and have
6-8 GB RAM, which makes them attractive for shell development. They are
**not** the first physical target: the OnePlus 6/6T are documented with
partial telephony and partial Wi-Fi, they depend on vendor firmware, and they
require bootloader unlocking. Revisit them after the QEMU and PinePhone gates,
with a separate ADR or an amendment.

## Unsupported cases

The following are explicitly out of scope for the first image:

1. **Android-based bases and Android userspaces.** AOSP, LineageOS, Halium,
   and Android app compatibility layers are not the OS base and are not
   assumed. This is not an Android derivative.
2. **Devices with only a downstream/vendor kernel and no mainline DRM/GPU.**
   Phosh does not work on downstream kernels on Nura; software-rendered
   Plasma Mobile is not a supported path.
3. **Devices not listed in Nura `community` or `testing`, or without a public
   device port.** No "it might boot" claims. A porting project needs its own
   decision.
4. **armv7/32-bit devices, x86_64 phones or tablets, generic PCs, laptops,
   and Chromebooks.** None is the reference class. `qemu-amd64` is a
   development convenience only, not a product target.
5. **SDM845/OnePlus 6-class devices in the first milestone.** Their upstream
   `community` status is acknowledged, but they are deferred; no image and no
   support claim until re-evaluated.
6. **Devices requiring bootloader-unlock exploits, leaked signing keys, or
   firmware that cannot be redistributed or documented as user-supplied.**
   No bypass instructions and no support promise. The PinePhone loads vendor
   firmware blobs for Wi-Fi/Bluetooth and the modem; their licences must be
   audited, and if they cannot be redistributed they need a documented
   user-supplied path.
7. **Feature promises not backed by the device matrix.** VoLTE, camera
   (especially the front camera), NFC, fingerprint, DRM streaming, Widevine,
   dual SIM, and 5G are not guaranteed by the base decision. Each is checked
   per device.
8. **Tablets, laptops, and convergence as a first-class target.** The first
   shell is touch-first phone UI, not a desktop-convergence product.

## Consequences

Positive:

- The project inherits device kernels, firmware packages, image creation, and
  a stable release channel instead of building them.
- `qemu-aarch64` gives an ARM64 reference before physical hardware.
- The PinePhone class gives a close-to-mainline-kernel, no-Android bring-up
  target.
- The Padilha palette engine can feed GTK and Qt, so the shared visual
  identity survives the interface choice.

Negative:

- Some desktop applications available on Arch may be missing from Alpine or
  need packaging for the phone.
- Phosh is GTK3 today, so the Quickshell shell code is not reused. M1 keeps
  Phosh's shell and adds a Padilha theme layer; a Padilha-specific mobile
  shell would be a new, touch-first implementation later.
- The PinePhone is slow and memory-constrained; it cannot validate
  performance for modern phones.
- Nura is a small community, `main` is empty, and device status can drift.
- `pmbootstrap` and `pmaports` are moving dependencies; a thin wrapper must be
  pinned and tested.

## Implementation notes for the next tasks

1. Pin the Nura stable release and `pmaports` commit; record artifact hashes.
2. Build a thin `pmbootstrap` wrapper for `qemu-aarch64` + Phosh. Do not
   reimplement partitioning, bootloader setup, or image assembly.
3. Add a Padilha overlay package: palette generator, wallpapers, fonts, icons,
   sounds, GTK theme output. No shell fork in the first milestone.
4. Add a QEMU boot/UI test: Phosh session, phone-like resolution, OSK, palette
   applied, screenshot artifact. Keep `qemu-amd64` as an optional fast smoke
   path only.
5. After QEMU passes, run the PinePhone physical checklist from an SD card.
   Do not claim support until it passes.
6. Write the supported/unsupported device matrix and recovery notes before
   any public image.
7. Revisit Plasma Mobile if Qt/QML shell reuse becomes a hard requirement;
   revisit SDM845 after the first physical gate.

## Risks for the next tasks

1. **`qemu-aarch64` is too slow or flaky for CI.** High likelihood, medium
   impact. Use `qemu-amd64` for quick smoke tests and make `qemu-aarch64` the
   release gate with a 30-minute budget to reach Phosh; cache `pmbootstrap`
   artifacts. Owner: CI. Trigger: two consecutive gate runs exceed 30 minutes
   or fail to boot.
2. **Upstream device status drifts or the wiki is stale.** Medium likelihood,
   high impact. Pin stable and `pmaports`, re-check the device page, package
   path, and image list immediately before a build, and record the checked
   date. The PinePhone page currently says "no pre-built images" while the
   install page lists a v26.06 image, and its device package is linked under
   `device/testing` despite a `community` label. Treat these as warnings, not
   details. Owner: build. Trigger: the page, package path, and image list
   disagree at build time.
3. **PinePhone performance or memory is insufficient for Phosh.** High
   likelihood, medium impact. Measure boot time and memory early; keep OpenRC
   as a Phosh fallback (Plasma would then need a separate systemd image); do
   not promise modern-phone performance. Owner: device bring-up. Trigger:
   first boot exceeds 2 minutes or the session OOMs under normal use.
4. **The shell-reuse gap is larger than expected.** High likelihood, high
   impact. M1 does not fork Phosh; the palette and tokens are the contract.
   Prototype one Padilha surface on Phosh to validate the theme pipeline, not
   to choose a shell. Owner: shell/theme. Trigger: the prototype needs a
   toolkit rewrite or cannot be expressed as a Phosh theme/session layer;
   then evaluate Plasma or a custom shell.
5. **`pmbootstrap`/`pmaports` changes break the wrapper.** Medium likelihood,
   medium impact. Keep the wrapper thin, pin versions, and run the image test
   in CI. Owner: build. Trigger: more than one wrapper patch per upstream
   release, or a pinned commit fails CI twice in a row.
6. **Firmware, licensing, or bootloader constraints block a device.** Medium
   likelihood, high impact. The PinePhone reduces bootloader and kernel
   vendor lock-in, but it still uses firmware blobs; audit and document their
   licenses, do not redistribute what the license forbids, and do not publish
   unlock bypasses. Owner: device/legal. Trigger: a target needs firmware we
   cannot ship or document as user-supplied.
7. **Telephony cannot be validated in QEMU.** High likelihood, medium impact.
   Keep calls, SMS, and mobile data in the physical checklist with a SIM, mark
   them unverified until then, and never claim daily-driver readiness from
   QEMU. Owner: device bring-up. Trigger: calls, SMS, or mobile data fail on
   the reference unit.
8. **Scope creep into "support every device".** Medium likelihood, high
   impact. Keep one reference class and the explicit unsupported list; a new
   device class requires an ADR amendment. Owner: maintainers. Trigger: a
   request to add a device outside the class before the first image ships.

## Verification and sources

No image was built, no device was flashed, and no hardware was purchased for
this ADR. Upstream feature tables are reported, not independently verified.
The checked date for web sources is 2026-11-06.

- Nura rename announcement:
  <https://nura.eco/blog/2026/09/27/nura-rename/>
- Nura state page (small community, not a polished OS):
  <https://nura.eco/state/>
- Nura install page, stable v26.06 and image list:
  <https://nura.eco/install/>
- Nura device categories and counts:
  <https://wiki.nura.eco/wiki/Devices>
- Nura QEMU aarch64:
  <https://wiki.nura.eco/wiki/QEMU_aarch64_(qemu-aarch64)>
- Nura QEMU amd64:
  <https://wiki.nura.eco/wiki/QEMU_amd64_(qemu-amd64)>
- Nura Phosh page (GTK3, OpenRC and systemd):
  <https://wiki.nura.eco/wiki/Phosh>
- Phosh development news, July 2026 (0.56 and GTK4 port):
  <https://phosh.mobi/posts/development-news-2026-07/>
- Nura Plasma Mobile page (Qt6, systemd required):
  <https://wiki.nura.eco/wiki/Plasma_Mobile>
- Nura interface guidance (downstream DRM limitation):
  <https://wiki.nura.eco/wiki/Category:Interface>
- Nura PinePhone page (community, mainline, feature table):
  <https://wiki.nura.eco/wiki/PINE64_PinePhone_(pine64-pinephone)>
- Nura OnePlus 6 page (community, mainline, partial telephony):
  <https://wiki.nura.eco/wiki/OnePlus_6_(oneplus-enchilada)>
- Arch Linux ARM platforms (no phone platform):
  <https://archlinuxarm.org/platforms>
- Arch Linux ARM about page (a port, rolling):
  <https://archlinuxarm.org/about>
- Arch Linux ARM generic aarch64 (mainline kernel and DTBs):
  <https://archlinuxarm.org/platforms/armv8/generic>
- Arch Linux ARM `phosh` package:
  <https://archlinuxarm.org/packages/aarch64/phosh>
- Arch Linux ARM `plasma-mobile` package:
  <https://archlinuxarm.org/packages/aarch64/plasma-mobile>
- Arch Linux x86_64 package search, for comparison:
  <https://archlinux.org/packages/?q=phosh>
- DanctNIX/Arch Mobile, the third-party PinePhone-oriented Arch layer:
  <https://github.com/dreemurrs-embedded/Pine64-Arch>
- Maria Padilha DE desktop shell and palette engine:
  <https://github.com/maria-padilha-os/maria-padilha-de>

## Revision history

- 2026-11-06: accepted.
