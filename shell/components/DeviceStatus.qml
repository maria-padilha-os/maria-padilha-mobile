// Real device status with demo fallbacks for offscreen screenshots and QEMU
// guests that do not expose UPower or NetworkManager.

import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Services.UPower

QtObject {
    id: root

    property bool demo: false

    readonly property var battery: UPower.displayDevice
    // Phones expose a normal Battery device, not UPower's isLaptopBattery
    // flag. Treat any ready, present battery as the display battery instead of
    // requiring the laptop heuristic.
    readonly property bool hasBattery: demo || (battery !== null && battery !== undefined &&
        battery.ready && battery.isPresent && battery.type === UPowerDeviceType.Battery)
    readonly property int batteryPercent: demo ? 82 : (hasBattery ? Math.round(battery.percentage * 100) : -1)
    readonly property string batteryState: {
        if (demo)
            return "Charging";
        if (!hasBattery)
            return "Unknown";
        switch (battery.state) {
        case UPowerDeviceState.Charging:
            return "Charging";
        case UPowerDeviceState.Discharging:
            return "Discharging";
        case UPowerDeviceState.Empty:
            return "Empty";
        case UPowerDeviceState.FullyCharged:
            return "Fully charged";
        case UPowerDeviceState.PendingCharge:
            return "Pending charge";
        case UPowerDeviceState.PendingDischarge:
            return "Pending discharge";
        default:
            return "Unknown";
        }
    }
    readonly property bool charging: demo
        ? true
        : (hasBattery ? [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(battery.state) : false)
    readonly property bool externalPower: demo ? true : !UPower.onBattery
    readonly property bool batteryLow: batteryPercent >= 0 && batteryPercent <= 20 && !charging
    readonly property bool batteryCritical: batteryPercent >= 0 && batteryPercent <= 5 && !charging
    readonly property real batterySeconds: {
        if (demo)
            return charging ? 5400 : 21600;
        if (!hasBattery)
            return -1;
        const seconds = charging ? battery.timeToFull : battery.timeToEmpty;
        return (seconds > 0 && isFinite(seconds)) ? seconds : -1;
    }
    readonly property string batteryTimeLabel: {
        const seconds = batterySeconds;
        if (!(seconds > 0))
            return "";
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.round((seconds % 3600) / 60);
        if (hours > 0)
            return hours + "h " + minutes + "m";
        return minutes + "m";
    }
    readonly property string batteryLabel: batteryPercent >= 0 ? batteryPercent + "%" : "AC"
    readonly property string batteryIcon: !hasBattery && !demo ? "power" : "battery"
    readonly property real batteryLevel: batteryPercent >= 0 ? batteryPercent / 100 : 1.0

    readonly property var connectedDevice: {
        if (demo)
            return null;
        const devices = Networking.devices.values;
        for (const device of devices) {
            if (device && device.connected)
                return device;
        }
        return null;
    }

    readonly property bool online: demo || connectedDevice !== null
    readonly property string networkLabel: {
        if (demo)
            return "Padilha Wi-Fi";
        const device = connectedDevice;
        if (!device)
            return Networking.connectivity === NetworkConnectivity.Full ? "Online" : "Offline";
        if (device.type === DeviceType.Wifi)
            return "Wi-Fi";
        if (device.type === DeviceType.Wired)
            return "Wired";
        return "Online";
    }
    readonly property string networkShort: {
        if (demo)
            return "Wi-Fi";
        const device = connectedDevice;
        if (!device)
            return Networking.connectivity === NetworkConnectivity.Full ? "On" : "Off";
        return device.type === DeviceType.Wired ? "LAN" : "Wi-Fi";
    }
    readonly property string networkIcon: online ? "wifi" : "wifi_off"
}
