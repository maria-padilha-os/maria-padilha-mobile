// Language and region settings. These reuse the desktop config keys rather
// than introducing a mobile-only locale file.

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
        text: "Language"
    }

    SettingsSelectRow {
        theme: root.theme
        icon: "person"
        label: "Interface language"
        description: "Stored as general.language; time formatting follows immediately"
        options: root.settings.supportedLanguages
        currentValue: root.settings.language
        onSelected: value => {
            root.settings.setLanguage(value);
            root.state.toast("Language · " + root.settings.languageLabel(value));
        }
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "search"
        label: "Current catalogue"
        value: root.settings.supportedLanguages.length + " choices"
        description: "Auto follows the system locale; unsupported values fall back to Auto."
    }

    SettingsSection {
        theme: root.theme
        text: "Time and region"
    }

    SettingsSelectRow {
        theme: root.theme
        icon: "clock"
        label: "Clock format"
        description: "Stored as services.clockFormat and applied immediately"
        options: root.settings.supportedClockFormats
        currentValue: root.settings.clockFormat
        onSelected: value => root.settings.setClockFormat(value)
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "clock"
        label: "Locale"
        value: root.settings.language.length > 0 ? root.settings.language : "System"
        description: "The mobile shell currently ships English strings."
    }

    SettingsSection {
        theme: root.theme
        text: "Scope"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "warning"
        label: "No second locale format"
        value: "Padilha config"
        description: "Values live in shell.json alongside the desktop settings."
    }
}
