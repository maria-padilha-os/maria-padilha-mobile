# Power, battery, thermal and suspend behaviour

Maria Padilha Mobile treats the phone as a battery-powered device, not a small
laptop. This page records the policy, the parts that are implemented in this
checkout, the parts that are staged for the image, and the limits that are not
claimed.

No image was built or flashed for this task. Nothing here is a physical-device
support claim, and suspend was **not** tested on the reference laptop.

## What is implemented

| Area | Implementation | Where |
| --- | --- | --- |
| Battery/charging state | UPower is the source of truth; the shell shows percentage, charging, low/critical state and time remaining | `shell/components/DeviceStatus.qml`, `shell/components/StatusBar.qml` |
| Charge thresholds | Hardware-gated `power_supply` attributes, default 20–80%; unsupported hardware is a no-op | `scripts/power-charge-thresholds.sh`, `config/power/power.conf` |
| Threshold scheduling | One oneshot service, one udev `add` rule, one `post` sleep hook — no timer and no daemon | `config/power/systemd/`, `scripts/power-sleep-hook.sh` |
| Thermal readings | Kernel `thermal_zone`/`hwmon` values with diagnostic warning and critical thresholds | `scripts/power-diagnostic.sh` |
| Suspend/resume policy | Suspend allowed; hibernation, hybrid sleep and suspend-then-hibernate disabled; logind idle overridden by Phosh | `config/power/systemd/sleep.conf.d/`, `config/power/systemd/logind.conf.d/` |
| Suspend test target guard | Refuses laptops, desktops, tablets and unclassified hosts; allows QEMU/phone-class targets | `scripts/power-suspend-check.sh` |
| Diagnostics | One-shot, read-only text or JSON report | `scripts/power-diagnostic.sh` |
| Image packages | `upower` and `lm-sensors` added to `extra_packages` | `config/power/power.conf`, `scripts/build.sh` |

`scripts/stage-power-config.sh` fills a staging root with the systemd,
udev, helper and documentation files. It never writes to `/etc`, `/usr` or
`/sys` on the running host. Installing that tree into an image is an explicit
root step for the image builder, separate from this checkout's unprivileged
checks.

## Battery and charging status

Phosh and the Quickshell prototype both consume UPower. The shell no longer
requires UPower's `isLaptopBattery` flag, which is false on a phone: any ready,
present `UPowerDeviceType.Battery` is treated as the display battery. The
status exposes:

- percentage and charge level;
- `Charging`, `Discharging`, `Fully charged`, `Empty`, pending or unknown
  state;
- whether external power is present;
- time to empty/full when UPower provides it;
- low (≤20%) and critical (≤5%) state while discharging.

If no battery is exposed, the shell shows `AC` and a power icon rather than a
fake percentage. QEMU usually has no phone battery, so that is the expected
guest display.

## Charge thresholds

The helper only writes the standard kernel attributes:

- `charge_control_start_threshold`
- `charge_control_end_threshold`

The default window is start 20%, end 80%, from `config/power/power.conf`.
Changing the policy is a reviewed config change; the rest of the helper reads
the same values.

Safety rules in the helper:

- `apply-if-supported` only: if neither attribute exists, it prints a no-op and
  exits successfully. No vendor-specific register, charger quirk or guessed
  sysfs name is used.
- A battery with `present != 1` is skipped.
- Values must be integers in 0–100 and `start < end`.
- `--apply` refuses to run without root; `--dry-run` is the default and is
  read-only. This repository's tests only use the dry run.
- Every write path is checked to be
  `<sysfs>/class/power_supply/*/charge_control_*_threshold`.

Many phones, including parts of the PinePhone/AXP803 class, do not expose the
standard end-threshold attribute in the pinned kernel. On those devices the
policy is a documented no-op, not a fake setting. `charge_behaviour` and
`charge_control_limit` are reported by the diagnostic but are not changed by
this helper.

Schedule:

- `maria-padilha-charge-thresholds.service` is `Type=oneshot` with no
  `Restart=` and no timer.
- A udev `add` rule requests that service when a `power_supply` appears.
- The systemd-sleep `post` hook re-applies the window after resume, because
  some charger drivers reset their registers across suspend.

Root installation is deliberately not performed by this checkout. See
[Known limitations](#known-limitations).

## Thermal readings

The diagnostic reads:

- `/sys/class/thermal/thermal_zone*/temp` and `type`;
- `/sys/class/hwmon/hwmon*/temp*_input` when no thermal zone is available.

Values are reported in degrees Celsius. `POWER_THERMAL_WARN_C` (65 °C) and
`POWER_THERMAL_CRITICAL_C` (80 °C) are diagnostic policy thresholds only; the
kernel's critical trip points remain authoritative. The image does not install
`thermald` (an x86-oriented daemon) and does not poll sensors in the
background. There is no fan control on the reference class.

## Suspend and resume policy

The policy is intentionally conservative:

- Suspend is allowed.
- Hibernation, hybrid sleep and suspend-then-hibernate are disabled. A phone
  has no safe swap/hibernate path in this milestone.
- Lid-switch actions are ignored. A future cover/dock must not suspend the
  phone by accident.
- The hibernate key is ignored; the suspend key still requests suspend.
- logind `IdleAction=ignore`. Phosh/gnome-settings-daemon owns idle display and
  suspend decisions. Running both paths would create a second, racing suspend
  trigger.
- The charge-threshold hook runs once after resume.

The actual suspend/resume test is manual and must be run **in QEMU or on a
supported device**, never on the reference laptop. See the
[manual QEMU power checklist](qemu-power-checklist.md).
`scripts/power-suspend-check.sh` is a target guard, not a suspend action: it
classifies the machine and refuses anything that is not QEMU or a phone-class
device.

## Diagnostic script

```sh
# human-readable, one scan, read-only
scripts/power-diagnostic.sh

# machine-readable JSON
scripts/power-diagnostic.sh --json

# inspect a mounted image or a test fixture instead of /sys
scripts/power-diagnostic.sh --sysfs /path/to/sysfs-root

# exit 1 when warnings are present (useful in a manual gate)
scripts/power-diagnostic.sh --strict
```

The JSON report includes `platform`, `battery.devices`, the charge-threshold
policy and support flags, `thermal.zones`, `suspend`, and `warnings`. The
script has no sleep loop and invokes no privileged command. It is safe to run
as the normal desktop user.

For a threshold plan without writing:

```sh
scripts/power-charge-thresholds.sh --dry-run
```

## No always-on background loops

The power work adds no polling daemon, no timer unit and no `while true` loop.
Every new process is one-shot:

- the diagnostic scans once and exits;
- the threshold helper scans once and exits;
- the systemd unit is `Type=oneshot`;
- the udev rule fires on a `power_supply` add event;
- the sleep hook runs once for `pre` and once for `post`.

This keeps the phone able to reach idle. `tests/power.sh` rejects a timer unit
or an always-on loop in the power scripts.

## Known limitations

1. **No image build, flash or physical run in this checkout.** The policy,
   helper, service, docs and tests are validated on the host only. A real
   image build needs the privileged builder described in
   [`docs/build.md`](build.md).
2. **QEMU is not a phone charger.** QEMU usually exposes no battery or
   threshold attribute. Battery and threshold paths are checked with sysfs
   fixtures; QEMU validates the suspend/resume path and the no-battery
   fallback, not AXP803 charging behaviour.
3. **Charge thresholds are hardware-dependent.** If the kernel does not expose
   the standard start/end attributes, nothing is written. The PinePhone class
   may be in that group for the pinned kernel. There is no vendor-specific
   fallback.
4. **Thermal readings are not thermal management.** The diagnostic reports
   values and the kernel handles critical trips. There is no userspace fan
   curve, CPU governor tuning or thermal daemon.
5. **Power profiles are not selected here.** `power-profiles-daemon` is not
   added; no CPU/GPU performance profile is promised.
6. **Suspend success depends on the device kernel, DRM, modem and firmware.**
   A successful QEMU suspend does not prove phone suspend, modem wake or
   display resume. The physical gate remains separate.
7. **Wake sources are reported, not curated.** The diagnostic counts enabled
   wakeups; it does not disable a modem, GPIO or USB wake source. That needs a
   device-specific decision.
8. **Phosh's own idle timeout is not configured by this repository.** The
   sleep/logind drop-ins prevent a second suspend path and remove unsafe
   hibernate targets; the GNOME power settings remain part of the Phosh
   session.
9. **Staging is not installation.** `scripts/stage-power-config.sh` produces a
   tree for the image builder. It intentionally does not copy into the live
   system or load systemd/udev.

## Verification

```sh
make check          # config, required files, shell syntax, secrets, checksums
make power-test     # power config, fixtures, JSON, threshold plan, target guard
make test           # full repository gate, including power and shell tests
```

`tests/power.sh` points the diagnostic at a fake sysfs tree with a battery,
charger, thresholds and thermal zones. It also checks the unsupported-hardware
no-op, the laptop suspend refusal and the staging tree. It never applies a
threshold and never suspends anything.
