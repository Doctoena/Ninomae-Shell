import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// A control centre row with a switch, for state that isn't a Config option (night light now): bind `on`, act in
// onSwitched. For Config options use ConfigSwitch
RowButton {
    id: root
    property bool on: false
    signal switched(bool on)
    onClicked: root.switched(!root.on)
    StyledSwitch {
        down: root.down
        sizeScale: 0.7
        checked: root.on
        onClicked: root.switched(checked)
    }
}
