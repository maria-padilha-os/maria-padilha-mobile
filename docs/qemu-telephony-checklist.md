# Manual QEMU telephony checklist

This is the manual gate for calls and SMS. It is **not** run by the repository
tests and this checkout does not claim a real call, a real SMS, working call
audio, a carrier result or physical-device support.

The automated side uses a real ModemManager session daemon with **no modem**
and an emulated ModemManager D-Bus service. Those checks prove the bridge and
the UI state model. Only this checklist, on a supported device or a QEMU guest
with a passed-through modem and a disposable test SIM, can exercise radio and
audio.

## Preconditions

- The checked `qemu-aarch64` image is built and booted by the documented
  builder path in [`docs/build.md`](build.md), or you are on a supported
  device that already has a working modem in ModemManager.
- The image contains `modemmanager` (`config/modem/modem.conf`).
- The checkout is available inside the guest for the shell, bridge and
  diagnostic commands.
- Use a **disposable test SIM and test number**. Do not use emergency services,
  a production number or a real personal conversation. SMS content used for
  the check must be a marker such as `padilha-sms-check-<random>`, not private
  text.
- Call audio may not work in this milestone. A call object reaching `active` is
  not an audio pass.

## 1. Host-side checks

```sh
make check
make modem-test
make shell-test
```

Expected: all pass. The output says a real ModemManager session was found with
no modem and that the emulated D-Bus service exercised calls/SMS. Those lines
are **not** a hardware result.

## 2. Guest sees ModemManager

Inside the guest:

```sh
mmcli -B
mmcli -L
scripts/telephony-bridge.py --once
```

Expected:

- `mmcli -B` reports the ModemManager version (1.24 or newer is the tested
  line).
- `mmcli -L` lists the modem, or reports no modem if this is the QEMU guest
  without a passed-through modem.
- `--once` emits one JSON snapshot. On a guest with no modem it must say
  `"state":"no-modem"` and exit 0, not crash.

Do not add `--debug` or `--log-personal-info` to ModemManager for this check.
Those options can write personal information.

## 3. No-modem UI state

On a QEMU guest without a passed-through modem, open the shell:

```sh
PADILHA_TELEPHONY_DEMO=0 PADILHA_TELEPHONY_BACKEND=off \
  quickshell -p "$PWD/shell"
```

Open **Calls** and **Messages** from the pinned apps or with:

```sh
qs ipc call padilha-shell calls
qs ipc call padilha-shell messages
```

Expected:

- both surfaces show **No modem** / the no-modem explanation;
- Dial, Send, Answer and Hangup actions are disabled or absent;
- the shell stays responsive and no telephony process is left running;
- the status bar does not show a modem/signal indicator.

Then run without `PADILHA_TELEPHONY_BACKEND=off`:

```sh
PADILHA_TELEPHONY_DEMO=0 quickshell -p "$PWD/shell"
```

Expected with a live ModemManager and no modem: `mmcli -L` reports no modems,
the bridge reports `no-modem`, and the surfaces still render that state.
If ModemManager is not running, the bridge reports `unavailable`; that is also
a pass for graceful handling.

## 4. Supported device or passed-through modem

Only continue if `mmcli -L` lists the modem and the SIM is unlocked.

```sh
mmcli -m any --output-json
scripts/telephony-bridge.py --once
```

Expected in the snapshot:

- a modem with `state` `registered` or `connected`;
- the operator name and a plausible signal quality;
- `capabilities.voice` and/or `capabilities.messaging` matching the modem;
- `locked` and no actions if the SIM still needs unlocking.

The shell should show the operator and only enable the capabilities the modem
reports. If the modem is emergency-only, ordinary dialing stays disabled.

## 5. SMS check

Use the disposable test number and marker. In **Messages**:

1. enter the test number and a marker body, then **Send**;
2. confirm the sent message moves from `sending` to `sent` in the list;
3. have the test number send the same marker back;
4. confirm the incoming message appears and can be replied to or deleted;
5. confirm the ModemManager state still reports the message rather than a
   local cache.

Expected with a working carrier/SIM:

- send is accepted and reaches `sent`;
- the incoming marker appears once;
- delete removes it from the list and from ModemManager storage where the
  modem supports deletion.

If the carrier, SIM or modem rejects SMS, record that as a device/carrier
failure; do not claim a pass and do not change the repository policy to work
around it.

## 6. Call check

Use the disposable test number. In **Calls**:

1. dial the number and confirm the call object moves through dialing to
   ringing/active;
2. hang up and confirm the call object is removed;
3. have the test number call the device and confirm **Answer** and **Decline**
   work;
4. confirm the UI returns to the dial state after hangup/decline.

Expected: call signalling works through ModemManager. **Audio is a separate
result.** If the earpiece/speaker/microphone does not work, record an audio
failure; the call object can be correct while audio is not implemented.

Do not test emergency calling. Do not leave a call open.

## 7. Privacy check

After using the marker SMS, inspect the shell, bridge and service output:

```sh
journalctl -b --no-pager | grep -F 'padilha-sms-check'
journalctl --user -b --no-pager | grep -F 'padilha-sms-check'
```

Expected: no output. The marker must not appear in a log. Also confirm the
bridge's stderr is empty during normal operation and that no `console.log`
telephony line exists in the shell output.

The message is allowed in the UI while the surface is open and in ModemManager's
on-modem storage. It must not be written by this repository to a local cache,
log file or journal.

## 8. Failure-state checks

Where the guest's service manager and test setup allow it, test at least:

- modem absent (`no-modem`);
- ModemManager stopped (`unavailable`, then recovery when it returns);
- SIM locked (`locked`, no PIN prompt);
- modem without Voice (Calls explains the limitation; SMS still works if
  Messaging is present);
- modem without Messaging (Messages explains the limitation; Calls still works
  if Voice is present).

Do not stop or restart a system service on a production device. Use a
disposable guest or the emulated service for these states. The automated
`tests/modem.sh` already covers them against the emulated D-Bus service.

## Pass criteria

A QEMU/device telephony gate passes only when:

- `make check`, `make modem-test` and `make shell-test` are clean;
- a no-modem guest renders the no-modem state without a crash or leftover
  process;
- the real modem is listed, registered and its capabilities are shown;
- an SMS to/from the disposable test number works;
- a call to/from the disposable test number can be dialled, answered and hung
  up (audio is recorded separately);
- the privacy marker does not appear in logs;
- failure states are graceful.

## No real call/SMS claim

The repository-side tests use a real ModemManager daemon with no modem and an
emulated ModemManager D-Bus service. They do **not** place a call, send an SMS,
prove carrier registration, prove audio, or qualify any phone. This checklist
is the only place where a real call/SMS result may be recorded, and it must
name the device, modem firmware, carrier, SIM and whether audio worked.

## No physical-device claim

A QEMU pass, with or without a passed-through modem, does not qualify a
PinePhone or any other handset. Physical support still needs the ADR 0001 gate:
SD boot, Phosh, touch, keyboard, Wi-Fi, audio, suspend/resume, modem detection,
calls, SMS, mobile data (carrier-dependent), FDE and recovery on a real unit.
