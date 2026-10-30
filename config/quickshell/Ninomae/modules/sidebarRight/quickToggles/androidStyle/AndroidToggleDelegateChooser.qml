pragma ComponentBehavior: Bound
import QtQuick
DelegateChooser {
    id: root
    property bool editMode: false
    required property real baseCellWidth
    required property real baseCellHeight
    required property real spacing
    required property int startingIndex
    signal openAudioOutputDialog()
    signal openAudioInputDialog()
    signal openBluetoothDialog()
    signal openNightLightDialog()
    signal openWifiDialog()
    role: "type"
    // Each tile reads its cell size, edit mode and position from this chooser (AndroidQuickToggleButton)
    DelegateChoice { roleValue: "network"; AndroidNetworkToggle { chooser: root; onOpenMenu: root.openWifiDialog() } }
    DelegateChoice { roleValue: "bluetooth"; AndroidBluetoothToggle { chooser: root; onOpenMenu: root.openBluetoothDialog() } }
    DelegateChoice { roleValue: "idleInhibitor"; AndroidIdleInhibitorToggle { chooser: root } }
    DelegateChoice { roleValue: "nightLight"; AndroidNightLightToggle { chooser: root; onOpenMenu: root.openNightLightDialog() } }
    DelegateChoice { roleValue: "gameMode"; AndroidGameModeToggle { chooser: root } }
    DelegateChoice { roleValue: "screenSnip"; AndroidScreenSnipToggle { chooser: root } }
    DelegateChoice { roleValue: "colorPicker"; AndroidColorPickerToggle { chooser: root } }
    DelegateChoice { roleValue: "mic"; AndroidMicToggle { chooser: root; onOpenMenu: root.openAudioInputDialog() } }
    DelegateChoice { roleValue: "audio"; AndroidAudioToggle { chooser: root; onOpenMenu: root.openAudioOutputDialog() } }
    DelegateChoice { roleValue: "notifications"; AndroidNotificationToggle { chooser: root } }
    DelegateChoice { roleValue: "powerProfile"; AndroidPowerProfileToggle { chooser: root } }
    DelegateChoice { roleValue: "antiFlashbang"; AndroidAntiFlashbangToggle { chooser: root; onOpenMenu: root.openNightLightDialog() } }
}
