import QtQuick
import qs.modules.common
Rectangle {
    id: root
    radius: Appearance.rounding.large
    color: "transparent" // Tiles sit straight on the drawer (each tile is its own pill)
    signal openAudioOutputDialog()
    signal openAudioInputDialog()
    signal openBluetoothDialog()
    signal openNightLightDialog()
    signal openWifiDialog()
}
