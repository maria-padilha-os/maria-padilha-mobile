# pine64-pinephone (deferred)

The physical reference class from ADR 0001 is a close-to-mainline aarch64
handset, exemplified by the PINE64 PinePhone.

This file only records the device choice. It is **not** a support claim and
this milestone does not build, partition, flash or boot a phone:

- `scripts/build.sh` rejects `--device pine64-pinephone`
- there is no flasher, partitioner or bootloader step in this repository
- a device is not supported until the physical checklist in the ADR passes on
  a real unit

The QEMU target must pass first. Physical work resumes only as a separate,
explicitly reviewed task.
