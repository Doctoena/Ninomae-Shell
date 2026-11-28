import QtQuick
import qs.modules.common
Rectangle {
    id: root
    color: "transparent" // The tiles draw themselves, straight on the sidebar
    signal openAudioOutputPage()
    signal openAudioInputPage()
    signal openBluetoothPage()
    signal openNightLightPage()
    signal openWifiPage()
}
