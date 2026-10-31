import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
/**
 * MaterialTextField for a secret (an API key): hidden as dots until the eye button shows it.
 * Single line, so editingFinished fires on Enter as well as on losing focus. secret: false makes it a
 * plain field in the same look (e.g. a server URL next to its key).
 */
MaterialTextField {
    id: root
    property bool secret: true
    property bool revealed: false
    echoMode: revealed || !secret ? TextInput.Normal : TextInput.Password
    wrapMode: TextInput.NoWrap
    rightPadding: secret ? revealButton.width + 12 : 14
    RippleButton {
        id: revealButton
        anchors {
            right: parent.right
            rightMargin: 6
            verticalCenter: parent.verticalCenter
        }
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: 11
        visible: root.secret && root.text.length > 0
        onClicked: root.revealed = !root.revealed
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: root.revealed ? "visibility_off" : "visibility"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledToolTip {
            text: root.revealed ? Translation.tr("Hide") : Translation.tr("Show")
        }
    }
}
