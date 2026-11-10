# ADR 0003: Cellular modem, calls and SMS

- **Status:** Accepted
- **Date:** 2026-11-10
- **Decision owner:** Maria Padilha Mobile maintainers
- **Related:** [ADR 0001](0001-mobile-base-and-reference-device.md),
  [Modem and telephony integration](../modem.md),
  [Manual QEMU telephony checklist](../qemu-telephony-checklist.md)

## Context

Maria Padilha Mobile is a Phosh image on postmarketOS/Nura. Some devices have
no modem at all, some have a modem but no usable SIM, some expose SMS but not
voice, and some may be in a failed or locked state. The shell must open Calls
and Messages without crashing or lying when any of those conditions is true.

The image already selects systemd, Phosh and NetworkManager through the Nura
Phosh UI ([ADR 0001](0001-mobile-base-and-reference-device.md)). The existing
Quickshell prototype owns the Padilha surfaces and palette. The telephony work
must therefore answer two questions:

1. which maintained component owns modem probing, SIM state and the modem
   protocols;
2. how much telephony UI and D-Bus glue the Padilha shell should own.

The task does not require mobile data, emergency calling, SIM unlock,
supplementary services or a particular dialer application. It does require a
working calls UI, SMS handling, graceful no-modem/modem-unavailable states and
a documented privacy contract.

## Decision

1. **ModemManager is the modem stack.** The image installs the
   `modemmanager` package, which provides the daemon, `mmcli` and the
   `org.freedesktop.ModemManager1` D-Bus API. ModemManager owns hardware
   probing, firmware/port selection, SIM state, voice-call objects and SMS
   objects. The repository does not implement AT, QMI, MBIM or CDMA commands.
2. **The shell talks to ModemManager through a small bridge.**
   `scripts/telephony-bridge.py` is a D-Bus client that projects ModemManager's
   `Modem.Voice` and `Modem.Messaging` objects into newline-delimited JSON for
   the Quickshell surfaces. It is not a second modem daemon and exits when the
   shell closes its stdin.
3. **The calls and SMS surfaces are Padilha QML.** `CallsSurface.qml` and
   `MessagesSurface.qml` use the existing theme, touch targets and navigation.
   The image does not add a second GTK dialer/messaging application for this
   milestone.
4. **Graceful states are first-class.** The bridge reports `no-modem`,
   `unavailable`, `locked`, `failed`, `disabled`, `searching` and `registered`.
   The surfaces render each state and disable actions that the modem or SIM
   cannot support.
5. **Privacy is part of the interface.** The shell keeps the current message
   list in memory only. It does not write message text, phone numbers, SIM
   PIN/PUK or IMSI to a log or a local cache. ModemManager is never started
   with `--log-personal-info`.

## Options considered

Scores are 1 (poor fit) to 5 (first-class fit) and are judgment calls for this
QEMU-first, Phosh-based milestone.

| Criterion | Weight | ModemManager + Padilha QML | oFono + Padilha QML | ModemManager + GNOME Calls/Messages |
| --- | ---: | ---: | ---: | ---: |
| Nura/Phosh integration | 25% | 5 | 2 | 4 |
| Voice + SMS API coverage | 25% | 5 | 4 | 5 |
| Maintenance and packaging | 20% | 5 | 3 | 3 |
| Calls/SMS UI fit with the shell | 15% | 4 | 4 | 2 |
| Privacy and log control | 15% | 5 | 3 | 3 |
| **Weighted result** | | **4.85** | **3.05** | **3.55** |

### ModemManager versus oFono

**ModemManager.** It is the default mobile-broadband daemon in the
postmarketOS/Nura and NetworkManager stack, is packaged for Alpine/Nura, and
exposes voice and messaging as stable D-Bus interfaces. Phosh images already
pull in NetworkManager, and NetworkManager's mobile-broadband path is built
around ModemManager. Choosing ModemManager therefore adds one package and one
D-Bus client, not a parallel connectivity stack.

**oFono.** oFono is a capable telephony daemon and is used by some mobile
projects, but it is not the default modem path in a Phosh/Nura image. Using it
would mean owning an additional daemon, its D-Bus activation, its interaction
with NetworkManager, and a second set of device quirks. That is exactly the
kind of duplicated integration ADR 0001 avoided.

### Why not only launch GNOME Calls and a GTK messaging app?

GNOME Calls and GNOME ecosystem messaging applications are maintained and can
consume ModemManager through libmm-glib. They would still need:

- extra runtime packages and a larger GTK/GNOME dependency set on a 2–3 GB
  reference class device;
- a separate visual language and navigation model from the Padilha shell;
- their own audio-routing and notification assumptions;
- an integration layer from the Quickshell prototype to those applications.

The mirror-image problem is that our QML surfaces are not a maintained dialer
implementation, so the repository owns their small amount of UI code. We accept
that cost because the surfaces reuse the existing Padilha components and call
the same maintained ModemManager API. The modem protocol, call state machine
and SMS storage are not reimplemented. If the Padilha surfaces grow into a
full dialer with contacts, call history and audio routing, this decision should
be revisited in favour of a maintained calls application.

### Rejected alternatives

- **Direct AT/QMI/MBIM handling in the shell.** Rejected: duplicates the hard
  device-support work and cannot be tested without a real modem.
- **A synthetic call/SMS implementation with no ModemManager.** Rejected: it
  would satisfy screenshots but not the product requirement, and it would make
  the UI state a fake rather than a projection of modem state.
- **Claiming a call/SMS result from the emulated service.** Rejected: the
  emulated service proves the bridge and UI, not radio, audio or carrier
  behaviour.

## Consequences

Positive:

- one maintained modem daemon and one documented D-Bus API;
- voice and SMS use ModemManager's existing call/SMS objects, including its
  on-modem SMS storage;
- no custom modem protocol, firmware or SIM handling in this repository;
- the no-modem, unavailable, locked and capability-limited states are explicit
  and testable without hardware;
- message text and credentials stay out of repository logs by construction.

Negative:

- **Call audio is device-specific and is not routed by this milestone.** The
  calls UI can create/answer/hang up a call; hearing and speaking require the
  device's audio path and a later integration task. A call that reaches
  `active` in the emulated service is not proof of working audio.
- **Emergency calls are not implemented or claimed.** The UI disables ordinary
  calls when the modem reports `EmergencyOnly`, and the policy records
  `MODEM_EMERGENCY_CALLS=false`. Emergency calling must be a separate,
  explicitly reviewed task with the correct regulatory and audio behaviour.
- **SIM unlock is delegated to the system.** A locked SIM is shown as `locked`;
  this shell does not ask for or store a PIN/PUK. The user must unlock it in
  the system settings.
- **Only one primary modem is presented.** ModemManager may expose several
  modems; the bridge lists them, but the surfaces use the first. Multi-SIM
  selection is out of scope.
- **MMS, USSD, cell broadcast, call waiting, conference calls, call history and
  contacts are out of scope.** The ModemManager interfaces remain available
  for a future task.
- **The bridge is a repository-owned adapter.** It is small and tested, but it
  is still code the project maintains. A future Quickshell Modem service or a
  maintained client could replace it without changing the user-facing stack.

## Privacy contract

- The shell does not persist messages. `MODEM_STORE_MESSAGES=false`; the current
  `MessagesSurface` list is in memory and is repopulated from ModemManager
  after a restart. ModemManager's on-modem storage is owned by the modem, not
  by this repository.
- `MODEM_STORE_CREDENTIALS=false`; no SIM PIN/PUK is requested by the shell.
- `MODEM_LOG_MESSAGE_CONTENT=false`, `MODEM_LOG_CREDENTIALS=false` and
  `MODEM_LOG_PHONE_NUMBERS=false`.
- The bridge emits message content on stdout only as the UI state. It never
  writes content to stderr, a file or a journal. Error replies carry a D-Bus
  error name, not the remote message (which may echo a number or text).
- ModemManager must not be started with `--log-personal-info`. `tests/modem.sh`
  rejects that flag and a bridge/QML console log.
- The lock surface shows notification counts only; it never shows message
  bodies or numbers.

## Verification

`tests/modem.sh` checks:

- the config, package, D-Bus interface names and no-storage/no-logging flags;
- the bridge compiles and its CLI is available;
- a **real ModemManager daemon** started on a private session bus with no modem
  produces the graceful `no-modem` snapshot;
- an **emulated ModemManager D-Bus service** exercises outgoing/incoming SMS,
  outgoing/incoming calls, answer, hangup, delete, no-modem, locked, no-voice,
  no-messaging and the ModemManager-vanished state;
- the bridge and emulated service do not write message text or numbers to
  stderr.

The emulated service is modelled on upstream ModemManager's
`tools/test-modemmanager-service.py` but adds Voice and Messaging interfaces.
It is not a modem. No real call was placed and no real SMS was sent for this
ADR. Physical call/SMS/audio verification remains part of the
[manual gate](../qemu-telephony-checklist.md) and the ADR 0001 physical gate.

## Sources

Checked 2026-11-10. These are upstream project statements, not measurements
from this repository.

- ModemManager project and D-Bus API overview:
  <https://www.freedesktop.org/wiki/Software/ModemManager/>
- ModemManager 1.x D-Bus interface specification, including
  `org.freedesktop.ModemManager1.Modem.Voice`,
  `org.freedesktop.ModemManager1.Modem.Messaging`,
  `org.freedesktop.ModemManager1.Call` and
  `org.freedesktop.ModemManager1.Sms`:
  <https://www.freedesktop.org/software/ModemManager/api/latest/>
- ModemManager `mmcli` manual page:
  <https://www.freedesktop.org/software/ModemManager/man/latest/mmcli.8.html>
- ModemManager test service used as the model for the emulated fixture:
  <https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/blob/main/tools/test-modemmanager-service.py>
- NetworkManager mobile broadband support and its ModemManager dependency:
  <https://networkmanager.dev/docs/api/latest/settings-gsm.html>
- oFono project:
  <https://git.kernel.org/pub/scm/network/ofono/ofono.git>
- GNOME Calls:
  <https://gitlab.gnome.org/GNOME/gnome-calls>

## Revision history

- 2026-11-10: accepted. ModemManager + Padilha QML calls/SMS surfaces selected;
  oFono and a GNOME Calls/Messages-first stack documented as alternatives.
