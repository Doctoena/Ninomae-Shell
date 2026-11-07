import QtQuick
import qs.modules.common
Rectangle {
    id: root
    radius: Appearance.rounding.large
    color: "transparent" // Tiles sit straight on the drawer (each tile is its own pill)
    signal openAudioOutputPage()
    signal openAudioInputPage()
    signal openBluetoothPage()
    signal openNightLightPage()
    signal openWifiPage()
}
