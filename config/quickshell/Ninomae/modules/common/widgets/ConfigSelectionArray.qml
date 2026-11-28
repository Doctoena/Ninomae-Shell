import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
Flow {
    id: root
    Layout.fillWidth: true
    spacing: 2
    property list<var> options: [
        {
            "displayName": "Option 1",
            "icon": "check",
            "value": 1
        },
        {
            "displayName": "Option 2",
            "icon": "close",
            "value": 2
        },
    ]
    // `option: "bar.cornerStyle"` reads and writes that option, with each entry's value as the option's own
    property string option: ""
    property var currentValue: option !== "" ? Config.get(option) : null
    signal selected(var newValue)
    Repeater {
        model: root.options
        delegate: SelectionGroupButton {
            id: paletteButton
            required property var modelData
            required property int index
            onYChanged: {
                if (index === 0) {
                    paletteButton.leftmost = true
                } else {
                    const prev = root.children[index - 1]
                    const thisIsOnNewLine = prev && prev.y !== paletteButton.y
                    paletteButton.leftmost = thisIsOnNewLine
                    prev.rightmost = thisIsOnNewLine
                }
            }
            leftmost: index === 0
            rightmost: index === root.options.length - 1
            buttonIcon: modelData.icon || ""
            buttonText: modelData.displayName
            toggled: root.currentValue == modelData.value
            onClicked: {
                if (root.option !== "") Config.set(root.option, modelData.value);
                root.selected(modelData.value);
            }
        }
    }
}
