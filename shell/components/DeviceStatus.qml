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
    readonly property bool hasBattery: demo || (battery !== null && battery !== undefined && battery.ready && battery.isLaptopBattery)
    readonly property int batteryPercent: demo ? 82 : (hasBattery ? Math.round(battery.percentage * 100) : -1)
    readonly property bool charging: demo
        ? true
        : (hasBattery ? [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(battery.state) : false)
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
