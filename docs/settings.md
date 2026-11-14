# Mobile settings

The touch settings surface is part of the Quickshell prototype in `shell/`. It
is not a second settings daemon and it does not replace Phosh's own settings
for system services. It gives the mobile shell a Padilha-styled place to read
device state and change the small set of preferences the shell owns.

## Pages

| Page | File | Changes |
| --- | --- | --- |
| Overview | `shell/surfaces/SettingsSurface.qml` | opens any page; landscape adds a persistent category rail |
| Network | `shell/settings/pages/NetworkSettingsPage.qml` | Wi-Fi radio, current connection, nearby networks through Quickshell's NetworkManager backend |
| Display | `shell/settings/pages/DisplaySettingsPage.qml` | backlight brightness, interface scale, live scale preview |
| Sound | `shell/settings/pages/SoundSettingsPage.qml` | default PipeWire sink volume and mute |
| Battery | `shell/settings/pages/BatterySettingsPage.qml` | UPower state, power profile, low-battery threshold, charging notifications |
| Language | `shell/settings/pages/LanguageSettingsPage.qml` | UI language, clock format and locale |
| About | `shell/settings/pages/AboutSettingsPage.qml` | device, image, shell, palette and config path |

The row components in `shell/settings/` are mobile ports of the desktop
Nexus common rows (`PageBase`, `SectionHeader`, `ToggleRow`, `SliderRow`,
`SelectRow`, `InfoRow`, `RowButton`, `StepperRow`). They keep the same grouped
card layout and interaction model but use the mobile `Theme` instead of the
desktop `Caelestia.Config`/`Tokens` modules, because the mobile image does not
install the desktop QML plugin.

All rows are at least 60 px high and every actionable target is at least 48 px.
The display-scale choices are 100%, 110% and 120%: only upscaling is offered so
the 48 px touch floor cannot be reduced. Text colours come from the guarded
`Theme` roles, so both the light palette and the dark fixture are readable.

## Persistence

Preferences are written to the existing Maria Padilha configuration file:

```
$PADILHA_CONFIG_DIR/shell.json
```

`PADILHA_CONFIG_DIR` defaults to `$XDG_CONFIG_HOME/padilha`, then
`~/.config/padilha`. The file is the same JSON the desktop shell reads; the
mobile app does not create a second settings file or schema. Writes are atomic
and unknown keys are preserved.

| Setting | Existing key |
| --- | --- |
| Interface scale | `appearance.font.scale` |
| UI language | `general.language` |
| Clock format | `services.clockFormat` |
| Critical battery level | `general.battery.criticalLevel` |
| Charging notifications | `utilities.toasts.chargingChanged` |

`PADILHA_SETTINGS_CAPTURE=1` also asks `padilha-config capture` to promote the
file into the desktop's generated `ui.lua`, matching the existing desktop
settings workflow. It is off by default so a minimal guest does not need the
desktop compiler.

Brightness and audio volume/mute are not duplicated into the config file:
the backlight subsystem and PipeWire/WirePlumber own that state. Wi-Fi state is
owned by NetworkManager. Battery state is read from UPower. Charge thresholds
remain owned by the image's hardware-gated helper; the settings UI never writes
them.

## Safety boundaries

- No privileged command is run from the settings surface. It uses Quickshell's
  `Networking`, `Pipewire` and `UPower` APIs and `brightnessctl` for the
  backlight only.
- The network page does not shell out to `nmcli`, `rfkill`, `ip` or `iw`.
- Automated tests run with `PADILHA_SHELL_DEMO=1`; device writes are suppressed.
  The self-test also asserts that the NetworkManager write counter stayed at
  zero.
- The only process launched by the About page is the read-only
  `quickshell --version` query, and it is skipped in demo mode.
- No screenshot or test in this repository captures a private window, a
  terminal, real Wi-Fi names or real system identifiers. Demo mode supplies the
  network, battery, host and device values used by the visual tests.

## Test hooks

| Variable | Effect |
| --- | --- |
| `PADILHA_SHELL_SURFACE=settings` | open the settings surface |
| `PADILHA_SHELL_SETTINGS_PAGE=index\|network\|display\|sound\|battery\|language\|about` | initial page |
| `PADILHA_CONFIG_DIR` | existing Padilha config directory |
| `PADILHA_SETTINGS_CONFIG` | explicit `shell.json` path, mainly for tests |
| `PADILHA_SETTINGS_WRITE=1` | allow writes in demo mode for the persistence test |
| `PADILHA_SETTINGS_SELFTEST=1` | exercise validation, navigation and a temp-config write |
| `PADILHA_SETTINGS_CAPTURE=1` | ask `padilha-config capture` after a save |

## Verification

```sh
make settings-test   # static policy, navigation/validation/persistence, all page renders
make shell-test      # existing shell, palette and responsive checks, plus settings
make test            # every repository check
```

The settings render pass covers 720x1280 and 1280x720 and a dark-palette pass.
`PADILHA_SHELL_SETTINGS_PAGE` selects the page for a screenshot:

```sh
for page in index network display sound battery language about; do
  PADILHA_SHELL_DEMO=1 PADILHA_SHELL_SIZE=720x1280 \
    PADILHA_SHELL_SURFACE=settings PADILHA_SHELL_SETTINGS_PAGE="$page" \
    PADILHA_SHELL_GRAB="$PWD/.scratch/screens/settings-$page.png" \
    QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=software \
    quickshell -p "$PWD/shell"
done
```

The surface is also reachable from the launcher's Settings tile, the Home
pinned grid, the Network quick action and IPC:

```sh
qs ipc call padilha-shell settings
qs ipc call padilha-shell settingsPage network
```
