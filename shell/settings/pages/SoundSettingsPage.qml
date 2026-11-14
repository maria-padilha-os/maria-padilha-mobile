// Sound settings: output volume and mute. Volume/mute live in PipeWire, which
// persists the default sink state itself; no extra settings file is created.

import QtQuick
import QtQuick.Layouts
import "../../components"
import ".."

SettingsPage {
    id: root

    required property Theme theme
    required property ShellState state
    required property bool landscape

    readonly property SettingsStore settings: root.state.settings

    SettingsSection {
        theme: root.theme
        first: true
        text: "Output"
    }

    SettingsSliderRow {
        theme: root.theme
        icon: root.settings.muted ? "volume" : "volume"
        label: "Media volume"
        description: root.settings.demo
            ? "Demo value; the real PipeWire sink is not touched"
            : (root.settings.audioAvailable
                ? "Stored by the audio server for the default output"
                : "No PipeWire output is available; showing a safe preview value")
        value: root.settings.volume
        valueLabel: Math.round(root.settings.volume * 100) + "%"
        enabled: !root.settings.muted
        onMoved: value => root.settings.setVolume(value)
    }

    SettingsToggleRow {
        theme: root.theme
        icon: root.settings.muted ? "volume" : "volume"
        label: "Mute output"
        description: root.settings.demo
            ? "Demo toggle; the real PipeWire sink is not touched"
            : "Mutes the default PipeWire sink"
        checked: root.settings.muted
        onToggled: checked => root.settings.setMuted(checked)
    }

    SettingsSection {
        theme: root.theme
        text: "Devices"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "volume"
        label: "Default output"
        value: root.settings.sink
            ? (root.settings.sink.description || root.settings.sink.name || "PipeWire sink")
            : "Unavailable"
        description: root.settings.audioAvailable
            ? "PipeWire / WirePlumber"
            : "The audio service did not report a sink."
    }

    SettingsSection {
        theme: root.theme
        text: "Scope"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "warning"
        label: "No system configuration writes"
        value: "PipeWire only"
        description: "This page never edits ALSA, WirePlumber or system config files."
    }
}
