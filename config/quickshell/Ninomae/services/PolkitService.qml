pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Polkit
Singleton {
    id: root
    property alias agent: polkitAgent
    property alias active: polkitAgent.isActive
    property alias flow: polkitAgent.flow
    property bool interactionAvailable: false
    property bool failed: false // The last attempt was wrong (cleared when typing starts again)
    function cancel() {
        root.flow.cancelAuthenticationRequest()
    }
    function submit(string) {
        root.flow.submit(string)
        root.interactionAvailable = false
    }
    Connections {
        target: root.flow
        function onAuthenticationFailed() {
            root.failed = true;
            root.interactionAvailable = true;
        }
    }
    PolkitAgent {
        id: polkitAgent
        onAuthenticationRequestStarted: {
            root.failed = false;
            root.interactionAvailable = true;
        }
    }
}
