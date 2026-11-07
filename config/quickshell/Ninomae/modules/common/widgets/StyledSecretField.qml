import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
/**
 * StyledTextField for a secret (an API key): hidden as dots until the eye button shows it.
 * Single line, so editingFinished fires on Enter as well as on losing focus. secret: false makes it a
 * plain field in the same look (e.g. a server URL next to its key). It's a Settings row: the card's colour, and
 * it joins the rows next to it into one group (GroupCorners).
 */
StyledTextField {
    id: root
    property bool secret: true
    property bool revealed: false
    echoMode: revealed || !secret ? TextInput.Normal : TextInput.Password
    wrapMode: TextInput.NoWrap
    rightPadding: secret ? revealButton.width + 12 : 14
    leftPadding: 16 // Lined up with the other rows' names
    implicitHeight: 56
    readonly property bool settingsRow: true
    GroupCorners { id: corners; item: root }
    background: TextFieldBackground {
        field: root
        restColor: Appearance.m3colors.m3surfaceContainer
        hoverColor: Appearance.m3colors.m3surfaceContainerHigh
        topRadius: corners.top
        bottomRadius: corners.bottom
    }
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
