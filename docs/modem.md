# Cellular modem, calls and SMS

Maria Padilha Mobile uses **ModemManager** as its cellular modem stack and a
small repository-owned D-Bus bridge to feed the Padilha calls and SMS surfaces.
The decision and the comparison with oFono and a GNOME Calls/Messages-first
stack are in [ADR 0003](adr/0003-modem-and-telephony.md).

This page describes the implemented pieces, the state model, the privacy
contract and what is **not** claimed. No image was built or flashed for this
task, no physical modem was used, and no real call or SMS was sent.

## Components

| Component | Path | Role |
| --- | --- | --- |
| Modem policy | `config/modem/modem.conf` | package, D-Bus names, privacy flags, emulation/test paths |
| Image package | `config/build.conf` | adds `modemmanager` to `extra_packages` |
| Telephony bridge | `scripts/telephony-bridge.py` | D-Bus client: projects ModemManager state to JSON, forwards dial/answer/hangup/SMS actions |
| Emulated ModemManager | `tests/modem/fake_modemmanager.py` | session-bus D-Bus fixture with Modem, Voice, Messaging, Call, Sms and Sim objects |
| Bridge integration test | `tests/modem/test_telephony_bridge.py` | call/SMS/state flow against the emulated service |
| Calls surface | `shell/surfaces/CallsSurface.qml`, `shell/components/CallCard.qml`, `shell/components/DialPad.qml` | dial pad, incoming call, answer/decline, active call hangup |
| SMS surface | `shell/surfaces/MessagesSurface.qml`, `shell/components/SmsCard.qml` | message list, reply, compose, send, delete |
| Telephony state | `shell/components/TelephonyService.qml` | process lifetime, JSON projection, in-memory calls/messages, demo mode |
| Status card | `shell/components/TelephonyStatusCard.qml` | shared no-modem/unavailable/capability/status rendering |
| Checks | `tests/modem.sh`, `tests/shell.sh` | static policy, real no-modem daemon, emulated call/SMS flow, UI renders and privacy |
| Manual gate | `docs/qemu-telephony-checklist.md` | supported-device call/SMS/audio checks; no hardware claim here |

The maintained component is ModemManager. The bridge is an adapter, not a
second modem daemon: it uses the documented
`org.freedesktop.ModemManager1` D-Bus API and exits when the shell closes its
stdin. The shell uses Quickshell's maintained `Process`, `SplitParser` and
`Theme` components, and the Padilha QML components already used by the other
surfaces.

The shell resolves the bridge relative to its own directory
(`Quickshell.shellPath("../scripts/telephony-bridge.py")`). A packaged image
must either install the bridge in that layout, install it at the path in
`MODEM_BRIDGE`, or set `PADILHA_TELEPHONY_BRIDGE` to the installed path. The
current image builder does not install the Quickshell prototype, so this is a
packaging step for the shell task rather than a root operation in this
checkout.

## D-Bus path

The modem stack is discovered through ModemManager's
`org.freedesktop.DBus.ObjectManager` at `/org/freedesktop/ModemManager1`.
The bridge subscribes to object/property changes and projects:

| Interface | Used for |
| --- | --- |
| `org.freedesktop.ModemManager1.Modem` | state, signal quality, SIM path, lock state, capabilities |
| `org.freedesktop.ModemManager1.Modem.Modem3gpp` | registration state and operator name |
| `org.freedesktop.ModemManager1.Modem.Voice` | call list, `CreateCall`, `HangupAll`, emergency-only flag |
| `org.freedesktop.ModemManager1.Call` | `Start`, `Accept`, `Hangup`, `SendDtmf`, state/direction/number |
| `org.freedesktop.ModemManager1.Modem.Messaging` | message list, `Create`, `Delete` |
| `org.freedesktop.ModemManager1.Sms` | state, direction/PDU type, number, text, timestamp, `Send` |
| `org.freedesktop.ModemManager1.Sim` | operator name and SIM presence; no IMSI is sent to the UI |

The bridge emits one JSON snapshot per change:

```json
{"type":"snapshot","schema":1,"backend":"ModemManager","available":true,
 "state":"registered","modems":[],"calls":[],"messages":[],
 "capabilities":{"voice":true,"messaging":true}}
```

Errors are emitted as `{"type":"error","code":"...","command":"..."}`. The
code is a token such as `no-modem`, `no-voice`, `no-messaging`, `no-call`,
`sim-locked` or a D-Bus error name. The remote error message is deliberately
not forwarded because it can contain a phone number or message text.

## No-modem and modem-unavailable states

The UI never treats a missing modem as a fatal shell error. The bridge and
`TelephonyService.qml` distinguish:

| State | Meaning | UI behaviour |
| --- | --- | --- |
| `starting` | bridge has not answered yet | status pill says starting; actions disabled |
| `no-modem` | ModemManager is reachable but has no modem object | Calls and Messages show "No modem" and the device explanation; actions disabled |
| `unavailable` | ModemManager is absent, stopped or unreachable on D-Bus | "ModemManager unavailable"; actions disabled; bridge retries every 5 s |
| `locked` | modem exists but the SIM needs unlocking | "SIM locked"; no PIN prompt and no stored credential |
| `failed` | ModemManager marked the modem failed | "Modem failed"; retry button |
| `disabled` | modem is powered down | "Modem disabled" |
| `initializing` / `searching` | modem is coming up or looking for a network | status shown; actions stay disabled until registered |
| `registered` / `connected` | modem has a network registration | actions depend on Voice/Messaging capability |
| capability-limited | Voice absent, Messaging absent or `EmergencyOnly` | Calls/SMS explain which capability is missing; only the available surface works |

`PADILHA_TELEPHONY_BACKEND=off` is a test hook that renders the no-modem state
without starting a process. `PADILHA_TELEPHONY_DEMO=1` supplies deterministic
in-memory state for screenshots; `PADILHA_TELEPHONY_DEMO=0` forces the real
backend path even when the shell demo flag is set.

The systemd service installed by the `modemmanager` package is the daemon's
normal lifecycle. This repository does not add a second service, timer,
polling loop or privileged installer.

## Calls

The calls surface uses the MM Voice interface:

1. the dial pad collects a number; the call button is enabled only when the
   modem is registered, Voice is available and `EmergencyOnly` is false;
2. the bridge calls `Voice.CreateCall({"Number": ...})` and then `Call.Start()`;
3. `Call.StateChanged`/properties update the card through the snapshot;
4. an incoming call appears as `ringing_in`; **Answer** calls `Call.Accept()`
   and **Decline** calls `Call.Hangup()`;
5. an active call has a **Hang up** action; the bridge falls back to
   `Voice.HangupAll()` if the call disappeared between snapshot and action;
6. DTMF is supported by the bridge (`Call.SendDtmf`) for a future keypad; the
   current surface does not expose a DTMF pad.

**Call audio is not routed by this milestone.** ModemManager exposes the call
object and may expose an `AudioPort`/`AudioFormat`; connecting that to the
device's speaker/microphone is device-specific work. A call reaching `active`
on the emulated service proves the D-Bus flow, not that audio works.

**Emergency calls are not implemented or claimed.**
`MODEM_EMERGENCY_CALLS=false`; the UI warns when the modem is emergency-only
and does not offer a fake emergency dialer. This needs a separate review.

**SIM PIN/PUK is not collected.** A locked SIM is shown as `locked`; unlock it
in the system settings. The shell never receives or stores the credential.

## SMS

The SMS surface uses the MM Messaging interface:

1. the bridge lists `Modem.Messaging.Messages` and each `Sms` object;
2. received messages arrive through `Messaging.Added` and appear in the list;
3. **Reply** fills the sender number; the compose panel accepts a number and
   text;
4. **Send** calls `Messaging.Create({"Number": ..., "Text": ...})` followed by
   `Sms.Send()`; the state moves through sending to sent;
5. **Delete** calls `Messaging.Delete(path)`.

The current list is in memory. The shell does not write a local message cache;
ModemManager's on-modem storage remains the source of truth for messages the
modem keeps. SMS text is not included in any `console.log`, journal line,
diagnostic file or test assertion on stderr.

MMS, USSD, cell broadcast, delivery reports beyond the `Sms` state, multi-part
composition and message search are out of scope for this milestone.

## Privacy contract

- `MODEM_STORE_MESSAGES=false` and `MODEM_STORE_CREDENTIALS=false`.
- `MODEM_LOG_MESSAGE_CONTENT=false`, `MODEM_LOG_CREDENTIALS=false` and
  `MODEM_LOG_PHONE_NUMBERS=false`.
- The bridge sends message text and numbers to the shell on stdout only because
  the UI has to display them. It never writes them to stderr, a file, the
  journal or a crash traceback.
- Error replies carry a D-Bus error name rather than the remote message.
- The telephony QML components contain no `console.log`/`console.warn`/
  `console.error` calls.
- The lock surface shows notification counts only; it does not reveal message
  bodies or numbers.
- Do not start ModemManager with `--log-personal-info`. `tests/modem.sh`
  rejects the flag, and the image uses the package default logging level.

This is a repository policy and a runtime check, not a formal audit of every
application in the guest or of the modem firmware. A compromised modem or
ModemManager is outside this contract.

## Test hooks

| Variable | Effect |
| --- | --- |
| `PADILHA_TELEPHONY_DEMO=1\|0` | force deterministic in-memory telephony state, or force the real backend |
| `PADILHA_TELEPHONY_BACKEND=auto\|off` | start the bridge, or render the no-modem state without a process |
| `PADILHA_TELEPHONY_BUS=session` | use the session bus instead of the system bus (tests/emulation only) |
| `PADILHA_TELEPHONY_BRIDGE=/path` | override the bridge path |
| `PADILHA_TELEPHONY_MESSAGE=...` | add one in-memory demo message, used to prove content is not logged |
| `PADILHA_SHELL_SURFACE=calls\|messages` | open a telephony surface for a render or demo |

The shell IPC also exposes `qs ipc call padilha-shell calls` and
`qs ipc call padilha-shell messages`. `status` includes the telephony state,
modem presence, operator and call/message counts, never their content.

## Verification

```sh
make modem-test       # policy, real no-modem ModemManager, emulated call/SMS flow
make shell-test       # QML lint, selftest, calls/messages renders and privacy
make test             # full repository gate
```

The emulated service is a **ModemManager D-Bus fixture**, modelled on upstream
`tools/test-modemmanager-service.py` and extended with Voice/Messaging. It is
not a modem. The real-daemon check starts `ModemManager --test-session` on a
private session bus with no hardware and verifies the graceful `no-modem`
snapshot. Neither check is a real call or SMS.

The manual path for a supported device or a QEMU guest with a passed-through
modem is [the QEMU telephony checklist](qemu-telephony-checklist.md). It
requires a disposable test number and never uses emergency services.

## Known limitations

1. **No real call, SMS, audio or carrier test in this checkout.** The emulated
   D-Bus service and a no-modem real daemon are the only automated checks.
2. **No call audio routing.** The device audio path, echo cancellation and
   speaker/earpiece switching are not implemented.
3. **No emergency calling.** Not claimed and not enabled in the policy.
4. **No SIM PIN/PUK UI.** Locked SIM is shown, not unlocked.
5. **One primary modem.** Multiple modem objects are listed by the bridge but
   the surfaces use the first. Multi-SIM is out of scope.
6. **No MMS/USSD/cell broadcast/contacts/call history.** The D-Bus interfaces
   exist but are not wired to UI.
7. **The bridge is repository-owned glue.** It is intentionally small, but a
   maintained Quickshell Modem service would be preferable if one becomes
   available.
8. **Physical support is still governed by ADR 0001.** A successful QEMU
   modem-emulation run does not qualify a PinePhone or any other handset.
9. **ModemManager's Voice/Messaging actions are polkit-protected.** The package
   defaults allow the active local session; a remote or inactive session can be
   denied. This repository does not install a polkit agent or change the policy.
