import QtQuick

// Soft fade over the edge of a sheet's scrolling list, in the sheet's colour, so items slide out of
// view instead of being cut off. Fades in only while there's more to scroll to on that side
Rectangle {
    id: root
    property color sheetColor
    property bool horizontal: false
    property bool reversed: false // false: solid at the top / left, true: at the bottom / right
    property bool active: true
    opacity: active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 150 } }
    gradient: Gradient {
        orientation: root.horizontal ? Gradient.Horizontal : Gradient.Vertical
        GradientStop { position: 0.0; color: root.reversed ? "transparent" : root.sheetColor }
        GradientStop { position: 1.0; color: root.reversed ? root.sheetColor : "transparent" }
    }
}
