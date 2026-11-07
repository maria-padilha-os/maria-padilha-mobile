# Base assumption for this scaffold

ADR 0001, *Mobile base and reference device*, is **not present on this
branch**. It was accepted on branch
`agent/20261106-200516-adr-choose-the-mobile-base-and-reference` at commit
`4691a14` (`docs/adr/0001-mobile-base-and-reference-device.md`).

This scaffold therefore records, rather than silently re-decides, the base
that ADR selects:

| Choice | Value |
| --- | --- |
| Base | postmarketOS (Alpine), now Nura, stable channel `v26.06` |
| Interface | Phosh, with a thin Padilha palette/theme layer later |
| Init | systemd |
| QEMU reference | `qemu-aarch64` |
| Physical reference | PinePhone-class aarch64, exemplified by `pine64-pinephone` |
| Build approach | thin wrapper around pinned `pmbootstrap` + `pmaports` |
| Android | not the base, not a fallback, not a runtime dependency |

The QEMU target is the only buildable target in this milestone. No phone is
required, and no device is flashed, partitioned, or claimed as supported.

## Pinning note

`config/build.conf` pins `pmbootstrap` `2.3.1` and both toolchain commits. The
`pmaports` commit is the snapshot this scaffold was authored against on
2026-11-07, not a claimed `v26.06` release tag: the upstream release branch is
not published in this checkout. Re-pin it to the exact `v26.06` release commit
before publishing an image, as described in [`docs/build.md`](build.md).

If ADR 0001 is merged, it is authoritative. Update or remove this note rather
than keeping two sources of truth.
