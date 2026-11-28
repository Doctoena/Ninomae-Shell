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
    // In a group (Captures' banner): its own 36 px square, joined to the ones beside it (rounded at the group's
    // ends), on: tinted in the accent. Set by the group. across: the group is a Row (else a Column)
    property bool joined: false
    property bool across: false
    readonly property int _joinIndex: joined ? (parent?.visibleChildren ?? []).indexOf(root) : -1
    readonly property int _joinCount: joined ? (parent?.visibleChildren ?? []).length : 0
    readonly property real _startRadius: _joinIndex === 0 ? Appearance.rounding.small : Appearance.rounding.joined
    readonly property real _endRadius: _joinIndex === _joinCount - 1 ? Appearance.rounding.small : Appearance.rounding.joined
    buttonRadiusTop: joined && !across ? _startRadius : -1
    buttonRadiusBottom: joined && !across ? _endRadius : -1
    buttonRadiusLeft: joined && across ? _startRadius : -1
    buttonRadiusRight: joined && across ? _endRadius : -1
    // A click doesn't take the keyboard: the details page keeps it, and passes keys on to the panels
    // (they sit outside it), so ←/→, Delete and Esc keep working after pressing one of these
    focusPolicy: Qt.NoFocus
    width: grouped && !joined ? 30 : 36; height: width; padding: 0
    buttonRadius: grouped ? Appearance.rounding.segment : Appearance.rounding.small
    // On the group's surface, or its own (close): a solid squircle, as the banners' chips
    colBackground: joined ? (active ? (danger ? Appearance.colors.colError : Appearance.colors.colLayer3Accent) : Appearance.colors.colLayer3)
        : active ? (danger ? Appearance.colors.colError : Appearance.colors.colPrimary)
        : grouped ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 1) : Appearance.colors.colLayer3
    colBackgroundHover: active ? (danger ? Appearance.colors.colError : joined ? Appearance.colors.colLayer3AccentHover : Appearance.colors.colPrimaryHover)
        : danger ? ColorUtils.transparentize(Appearance.colors.colError, 0.85) : grouped && !joined ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer3Hover
    colRipple: danger ? ColorUtils.transparentize(Appearance.colors.colError, 0.7) : grouped ? Appearance.colors.colLayer2Active : Appearance.colors.colLayer3Active
    contentItem: Item {
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.iconName
            iconSize: 18
            fill: root.joined && root.active ? 1 : 0
            color: root.active ? (root.danger ? Appearance.colors.colOnError : root.joined ? Appearance.colors.colPrimary : Appearance.colors.colOnPrimary)
                : root.danger && root.hovered ? Appearance.colors.colError : root.joined ? Appearance.colors.colOnLayer3 : Appearance.colors.colOnLayer2
            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }
    StyledToolTip { text: root.tip; visible: root.tip !== "" && root.hovered }
}
