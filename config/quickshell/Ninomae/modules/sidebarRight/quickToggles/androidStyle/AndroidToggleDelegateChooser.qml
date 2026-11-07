pragma ComponentBehavior: Bound
import QtQuick
DelegateChooser {
    id: root
    property bool editMode: false
    required property real baseCellWidth
    required property real baseCellHeight
    required property real spacing
    required property int startingIndex
    signal openAudioOutputPage()
    signal openAudioInputPage()
    signal openBluetoothPage()
    signal openNightLightPage()
    signal openWifiPage()
    role: "type"
    // Each tile reads its cell size, edit mode and position from this chooser (AndroidQuickToggleButton)
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
