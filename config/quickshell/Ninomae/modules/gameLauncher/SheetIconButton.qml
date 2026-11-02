import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

// Icon button for the sheets' and panels' headers (open in browser, open folder…). grouped: one of the
// header's action group (a 30 px segment on the group's surface); not grouped: on its own (close)
RippleButton {
    id: root
    property string iconName
    property string tip: ""
    property bool grouped: true
    property bool danger: false // Destructive (Move to Trash): red on hover
    property bool active: false // A mode that's on (Clips' Trim): the accent squircle behind the icon. With danger:
                                // red instead (Trash armed, waiting for the second click)
    // A click doesn't take the keyboard: the details page keeps it, and passes keys on to the panels
    // (they sit outside it), so ←/→, Delete and Esc keep working after pressing one of these
    focusPolicy: Qt.NoFocus
    width: grouped ? 30 : 36; height: width; padding: 0
    buttonRadius: grouped ? Appearance.rounding.segment : Appearance.rounding.container
    // On colLayer2: the group's surface, or its own (close), a step up from the panel
    colBackground: active ? (danger ? Appearance.colors.colError : Appearance.colors.colPrimary)
        : grouped ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 1) : Appearance.colors.colLayer2
    colBackgroundHover: active ? (danger ? Appearance.colors.colError : Appearance.colors.colPrimaryHover)
        : danger ? ColorUtils.transparentize(Appearance.colors.colError, 0.85) : Appearance.colors.colLayer2Hover
    colRipple: danger ? ColorUtils.transparentize(Appearance.colors.colError, 0.7) : Appearance.colors.colLayer2Active
    contentItem: Item {
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.iconName
            iconSize: 18
            color: root.active ? (root.danger ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary)
                : root.danger && root.hovered ? Appearance.colors.colError : Appearance.colors.colOnLayer2
            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }
    StyledToolTip { text: root.tip; visible: root.tip !== "" && root.hovered }
}
