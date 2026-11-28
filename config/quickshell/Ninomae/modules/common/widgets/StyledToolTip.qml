import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
ToolTip {
    id: root
    property bool extraVisibleCondition: true
    property bool alternativeVisibleCondition: false
    property color backgroundColor: Appearance?.colors.colTooltip ?? "#3C4043"
    property color textColor: Appearance?.colors.colOnTooltip ?? "#FFFFFF"
    readonly property bool internalVisibleCondition: (extraVisibleCondition && !!parent && (parent.hovered === undefined || parent.hovered)) || alternativeVisibleCondition
    verticalPadding: 5
    horizontalPadding: 10
    background: null
    font {
        family: Appearance.font.family.main
        variableAxes: Appearance.font.variableAxes.main
        pixelSize: Appearance?.font.pixelSize.smaller ?? 14
        hintingPreference: Font.PreferNoHinting // Prevent shaky text
    }
    visible: internalVisibleCondition
    contentItem: StyledToolTipContent {
        id: contentItem
        font: root.font
        text: root.text
        shown: root.internalVisibleCondition
        horizontalPadding: root.horizontalPadding
        verticalPadding: root.verticalPadding
        backgroundColor: root.backgroundColor
        textColor: root.textColor
    }
}
