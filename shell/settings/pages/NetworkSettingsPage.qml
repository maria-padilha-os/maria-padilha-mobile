// Network settings: Wi-Fi radio, current connection and nearby networks.
// All changes go through Quickshell's NetworkManager backend. Automated runs
// use SettingsStore.demo, which never touches the radio.

import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import "../../components"
import ".."

SettingsPage {
    id: root

    required property Theme theme
    required property ShellState state
    required property bool landscape

    readonly property SettingsStore settings: root.state.settings
    readonly property var networks: root.settings.wifiNetworks

    function securityLabel(network) {
        if (!network)
            return "";
        if (network.security === WifiSecurityType.Open)
            return "Open";
        return network.known ? "Saved · secured" : "Secured";
    }

    function connect(network) {
        if (!network || network.connected)
            return;
        if (root.settings.connectNetwork(network))
            root.state.toast("Connecting to " + network.name);
        else
            root.state.toast("Demo mode · network unchanged");
    }

    SettingsSection {
        theme: root.theme
        first: true
        text: "Connection"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: root.state.device.networkIcon
        label: "Current network"
        value: root.state.device.networkLabel
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "signal"
        label: "Address"
        value: root.settings.wifiAddress.length > 0 ? root.settings.wifiAddress : "Not connected"
        description: root.settings.wifiInterface.length > 0
            ? root.settings.wifiInterface : "No Wi-Fi device"
    }

    SettingsToggleRow {
        theme: root.theme
        icon: "wifi"
        label: "Wi-Fi"
        description: root.settings.demo
            ? "Demo switch; the real radio is not touched"
            : (root.settings.wifiSupported
                ? "Radio and scanning are managed by NetworkManager"
                : "No Wi-Fi hardware was reported")
        checked: root.settings.wifiEnabled
        enabled: root.settings.wifiSupported
        onToggled: checked => {
            const next = root.settings.setWifiEnabled(checked);
            root.state.toast(next ? "Wi-Fi on" : "Wi-Fi off");
        }
    }

    SettingsSection {
        theme: root.theme
        text: "Available networks"
    }

    SettingsInfoRow {
        theme: root.theme
        visible: !root.settings.wifiSupported
        icon: "wifi_off"
        label: "No Wi-Fi device"
        value: "—"
        description: "NetworkManager did not report a wireless interface."
    }

    SettingsInfoRow {
        theme: root.theme
        visible: root.settings.wifiSupported && root.networks.length === 0
        icon: "search"
        label: "No networks found"
        value: root.settings.wifiEnabled ? "Scanning" : "Wi-Fi off"
        description: root.settings.wifiEnabled
            ? "Move closer to an access point or try again."
            : "Turn Wi-Fi on to scan for networks."
    }

    Repeater {
        model: root.settings.wifiNetworks

        delegate: SettingsActionRow {
            id: networkRow
            required property var modelData

            theme: root.theme
            icon: networkRow.modelData.connected ? "check" : "wifi"
            label: networkRow.modelData.name
            description: root.securityLabel(networkRow.modelData) +
                " · signal " + Math.round(networkRow.modelData.signalStrength) + "%"
            trailingIcon: networkRow.modelData.connected ? "check" : "chevron_right"
            enabled: root.settings.wifiEnabled && !networkRow.modelData.connected
            onClicked: root.connect(networkRow.modelData)
        }
    }

    SettingsSection {
        theme: root.theme
        text: "Scope"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "warning"
        label: "No destructive test changes"
        value: "Demo-safe"
        description: "Automated tests render this page with the real radio untouched."
    }
}
