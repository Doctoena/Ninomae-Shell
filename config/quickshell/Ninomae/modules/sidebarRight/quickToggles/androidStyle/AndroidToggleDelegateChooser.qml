pragma ComponentBehavior: Bound
import QtQuick
DelegateChooser {
    id: root
    property var panel: null // The AndroidQuickPanel: dragging in edit mode
    property bool editMode: false
    property bool unused: false // In edit mode's list of toggles not in use
    // Where the row sits in its block and how wide its tiles are (AndroidQuickPanel): the tiles round off the
    // block's outer corners from these
    required property int rowIndex
    required property int rowCount
    required property int rowLength
    required property real cellWidth
    required property real cellHeight
    signal openAudioOutputPage()
    signal openAudioInputPage()
    signal openBluetoothPage()
    signal openNightLightPage()
    signal openWifiPage()
    role: "type"
    // Each tile reads its size, place and edit mode from this chooser (AndroidQuickToggleButton)
    DelegateChoice { roleValue: "network"; AndroidNetworkToggle { chooser: root; onOpenMenu: root.openWifiPage() } }
    DelegateChoice { roleValue: "bluetooth"; AndroidBluetoothToggle { chooser: root; onOpenMenu: root.openBluetoothPage() } }
    DelegateChoice { roleValue: "idleInhibitor"; AndroidIdleInhibitorToggle { chooser: root } }
    DelegateChoice { roleValue: "nightLight"; AndroidNightLightToggle { chooser: root; onOpenMenu: root.openNightLightPage() } }
    DelegateChoice { roleValue: "gameMode"; AndroidGameModeToggle { chooser: root } }
    DelegateChoice { roleValue: "screenSnip"; AndroidScreenSnipToggle { chooser: root } }
    DelegateChoice { roleValue: "colorPicker"; AndroidColorPickerToggle { chooser: root } }
    DelegateChoice { roleValue: "mic"; AndroidMicToggle { chooser: root; onOpenMenu: root.openAudioInputPage() } }
    DelegateChoice { roleValue: "audio"; AndroidAudioToggle { chooser: root; onOpenMenu: root.openAudioOutputPage() } }
    DelegateChoice { roleValue: "notifications"; AndroidNotificationToggle { chooser: root } }
    DelegateChoice { roleValue: "powerProfile"; AndroidPowerProfileToggle { chooser: root } }
    DelegateChoice { roleValue: "antiFlashbang"; AndroidAntiFlashbangToggle { chooser: root; onOpenMenu: root.openNightLightPage() } }
}
