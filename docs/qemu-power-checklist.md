# Manual QEMU power and suspend checklist

This checklist is the validation gate for the power policy. It is manual: run
it in the QEMU guest or on a supported device. **Do not run the suspend step on
the reference laptop or any desktop.** The target guard in step 3 enforces that
rule for the automated part.

No image was built or flashed for the repository-side power task, so this
checklist is not a claim that QEMU suspend has passed here.

## Preconditions

- The checked `qemu-aarch64` image is built and booted by the documented
  builder path in [`docs/build.md`](build.md).
- This checkout is available inside the guest, or the diagnostic and guard
  scripts have been copied in.
- The guest user can run ordinary commands. The checklist does not require
  root; the image-builder installation of the power drop-ins is a separate
  step.
- The QEMU monitor is available for a wake command (for example, a second
  terminal running the monitor socket used by the builder).

## 1. Host-side, before boot

```sh
make check
make power-test
scripts/power-diagnostic.sh --json
```

Expected: checks pass; the diagnostic produces valid JSON and exits 0. On a
laptop it reports the laptop warning, and that is fine for a diagnostic run.
Do not proceed to a suspend test on this host.

## 2. Guest sees the expected platform

Inside the QEMU guest:

```sh
scripts/power-diagnostic.sh
```

Expected:

- platform is classified as QEMU (or an explicitly supported device);
- no battery is a warning, not a crash, because QEMU normally has no phone
  charger;
- charge-threshold support may be false; the policy still reports a desired
  20–80% window;
- thermal zones are reported if the guest kernel exposes them;
- suspend states include `mem` or `freeze`.

Save the JSON form if a review artifact is wanted:

```sh
scripts/power-diagnostic.sh --json > power-before.json
```

## 3. Confirm the target is allowed

```sh
scripts/power-suspend-check.sh
```

Expected in QEMU or on a supported phone: `ALLOW`, exit 0. On a laptop,
desktop, tablet or unclassified machine: `REFUSE`, exit 1. Stop if it refuses;
**do not** work around the guard.

The guard never suspends anything. It only reads devicetree/DMI and
`/sys/power`.

## 4. Read the suspend policy

Inside the guest, check that the staged drop-ins landed and that unsafe targets
are absent:

```sh
cat /sys/power/state
cat /sys/power/mem_sleep
cat /etc/systemd/sleep.conf.d/10-maria-padilha-sleep.conf
cat /etc/systemd/logind.conf.d/10-maria-padilha-power.conf
```

Expected: `AllowHibernation=no`, `AllowHybridSleep=no`,
`AllowSuspendThenHibernate=no`, `IdleAction=ignore`, `HandleLidSwitch=ignore`.
If the staging tree was not installed into the image, record that as a failed
image-packaging step rather than editing the live system from this checklist.

## 5. Suspend and resume in QEMU

Only after step 3 printed `ALLOW`, request one suspend from the guest session:

```sh
loginctl suspend
```

The guest should suspend. From the QEMU monitor, wake it with the monitor's
system-wake command (`system_wakeup`) or the configured keyboard wake. Do not
use this step on the host laptop.

After resume:

```sh
script -q -c 'journalctl -b -o short-monotonic' /tmp/power-resume.log
grep -iE 'suspend|resume|hibernat|maria-padilha' /tmp/power-resume.log
scripts/power-diagnostic.sh --json > power-after.json
```

Expected:

- the guest comes back to the session and the display is usable;
- the journal shows a suspend entry and a resume entry for the same boot;
- no hibernate/hybrid target is attempted;
- the charge-threshold helper ran once on resume (or logged that no hardware
  attribute exists);
- no new long-running process or timer was created by the power policy.

## 6. Charge-threshold dry run

Inside the guest or on a supported device:

```sh
scripts/power-charge-thresholds.sh --dry-run
```

Expected: a plan for supported `charge_control_*_threshold` attributes, or a
clean no-op for unsupported hardware. The command must not change any value.
Do not use `--apply` in this checklist unless a separate, explicitly reviewed
root test on a disposable device requires it.

## 7. Idle check

Leave the guest idle for several minutes, then check that the power helper did
not create a busy process:

```sh
ps -eo pid,comm,args | grep -E 'power-(diagnostic|charge|sleep)|maria-padilha'
```

Expected: no diagnostic or helper process still running. A one-shot unit may
have exited. `systemd` and Phosh processes are outside the scope of this
check; the point is that the power policy adds no always-on loop.

## Pass criteria

All of the following must hold for a QEMU power gate:

- `make check`, `make power-test` and the diagnostic JSON are clean on the host;
- the guest diagnostic does not crash with no battery;
- the target guard prints `ALLOW`;
- one suspend/resume cycle works and the session is usable afterwards;
- no hibernation/hybrid target is attempted;
- the threshold helper is a no-op or an explicit, hardware-supported plan;
- no power helper is left running.

## No physical-device claim

A QEMU pass does not qualify a phone. Physical support still needs the ADR 0001
gate: SD boot, Phosh, touch, keyboard, Wi-Fi, audio, suspend/resume, modem
detection, calls, SMS, mobile data (carrier-dependent), FDE and recovery on a
real unit. This checklist only prevents an unsafe suspend test on a laptop and
gives the QEMU side a repeatable procedure.
