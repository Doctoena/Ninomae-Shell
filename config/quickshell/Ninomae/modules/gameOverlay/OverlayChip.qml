import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// A small button on the in-game overlay: a folder, Clear. Its icon, and a name when it has one (none: a square
// icon button, its tooltip says what it does). On a glass background over a picture (overPicture: a capture's
// buttons, white on dark). danger: red (Trash), armed: filled red (click again)
RippleButton {
    id: root
    property string iconName
    property string label: ""
    property string tip: ""
    property bool overPicture: false
    property bool danger: false
    property bool armed: false
    readonly property color fg: armed ? Appearance.colors.colOnError : danger ? Appearance.colors.colError
        : overPicture ? "white" : Appearance.colors.colOnLayer3
    implicitWidth: label === "" ? 30 : row.implicitWidth + 20
    implicitHeight: 30
    buttonRadius: Appearance.rounding.segment
    colBackground: armed ? Appearance.colors.colError : overPicture ? Qt.rgba(0, 0, 0, 0.55) : Appearance.colors.colLayer3
    colBackgroundHover: armed ? Appearance.colors.colError : overPicture ? Qt.rgba(0, 0, 0, 0.75) : Appearance.colors.colLayer3Hover
    colRipple: overPicture ? Qt.rgba(1, 1, 1, 0.2) : Appearance.colors.colLayer3Active
    contentItem: Item {
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 5
            MaterialSymbol {
                text: root.iconName
                iconSize: 17
                color: root.fg
            }
            StyledText {
                visible: root.label !== ""
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.fg
            }
        }
    }
    StyledToolTip {
        extraVisibleCondition: root.hovered && root.tip !== ""
        text: root.tip
    }
}
