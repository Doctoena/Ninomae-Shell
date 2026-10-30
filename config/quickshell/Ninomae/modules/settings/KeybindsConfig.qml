pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
// Keybinds (formerly the cheatsheet overlay): one card per category, read live from Hyprland.
// Binds come from the `description` in keybinds.lua ("Category: What it does").
ContentPage {
    id: page
    property string query: ""
    // Settings search opens this page on a keybind: fill the search with it
    function applyQuery(text) { searchField.text = text; }
    readonly property var keySubstitutions: ({
        "Super": "󰖳",
        "mouse_up": "Scroll ↓",
        "mouse_down": "Scroll ↑",
        "mouse:272": "LMB",
        "mouse:273": "RMB",
        "mouse:275": "MouseBack",
        "Slash": "/",
        "Hash": "#",
        "Return": "Enter",
        "Period": ".",
        "Escape": "Esc",
        "Minus": "-",
        "Equal": "=",
        "grave": "`",
        "mouse:274": "MMB",
        "Left": "←",
        "Right": "→",
        "Up": "↑",
        "Down": "↓",
        "BracketLeft": "[",
        "BracketRight": "]",
        "Semicolon": ";",
        "Apostrophe": "'",
        "Space": "Space",
    })
    readonly property list<string> categoryOrder: ["Shell", "Apps", "Window", "Workspace", "Screen", "Media", "Session"]
    readonly property var categoryIcons: ({
        "Shell": "widgets",
        "Window": "select_window",
        "Workspace": "space_dashboard",
        "Media": "music_note",
        "Session": "power_settings_new",
        "Screen": "screenshot_region",
        "Apps": "apps",
    })
    // Flatten the service's columns into one list of sections, filtered by the search
    readonly property var sections: {
        const q = page.query.trim().toLowerCase();
        const result = [];
        for (const column of HyprlandKeybinds.keybinds.children) {
            for (const section of column.children) {
                const binds = section.keybinds.filter(bind => q.length === 0
                    || bind.comment.toLowerCase().includes(q)
                    || section.name.toLowerCase().includes(q)
                    || [...bind.mods, bind.key].join(" ").toLowerCase().includes(q));
                const merged = [];
                for (const bind of binds) {
                    const keys = [...bind.mods, bind.key].filter(k => k !== "Super_L" && k !== "Super_R");
                    const same = merged.find(m => m.comment === bind.comment);
                    if (same) same.combos.push(keys);
                    else merged.push({ comment: bind.comment, combos: [keys] });
                }
                if (merged.length > 0) result.push({ name: section.name, keybinds: merged });
            }
        }
        const rank = name => {
            const i = page.categoryOrder.indexOf(name);
            return i < 0 ? page.categoryOrder.length : i;
        };
        return result.sort((a, b) => rank(a.name) - rank(b.name));
    }

    // Search pill
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 44
        radius: Appearance.rounding.container
        color: Appearance.m3colors.m3surfaceContainer
        border.width: searchField.activeFocus ? 2 : 0
        border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45)
        MaterialSymbol {
            id: searchIcon
            anchors {
                left: parent.left
                leftMargin: 16
                verticalCenter: parent.verticalCenter
            }
            text: "search"
            iconSize: 20
            color: Appearance.colors.colPrimary
        }
        TextField {
            id: searchField
            anchors {
                left: searchIcon.right
                leftMargin: 8
                right: parent.right
                rightMargin: 16
                verticalCenter: parent.verticalCenter
            }
            background: null
            padding: 0
            color: Appearance.colors.colOnLayer1
            placeholderText: Translation.tr("Search keybinds")
            placeholderTextColor: Appearance.colors.colSubtext
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.small
            selectionColor: Appearance.colors.colSecondaryContainer
            onTextChanged: page.query = text
            Component.onCompleted: forceActiveFocus()
        }
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 20
        visible: page.sections.length === 0
        horizontalAlignment: Text.AlignHCenter
        text: page.query.length > 0 ? Translation.tr("No keybinds match \"%1\"").arg(page.query) : Translation.tr("Loading keybinds…")
        color: Appearance.colors.colSubtext
    }

    Repeater {
        model: page.sections
        delegate: ContentSection {
            id: section
            required property var modelData
            title: modelData.name
            icon: page.categoryIcons[modelData.name] ?? "keyboard"
            spacing: 0
            GridLayout {
                id: bindGrid
                Layout.fillWidth: true
                columns: width >= 820 ? 2 : 1
                rows: Math.ceil(section.modelData.keybinds.length / columns)
                flow: GridLayout.TopToBottom // Down the first column, then the second, as you read
                columnSpacing: 24
                rowSpacing: 0
                uniformCellWidths: true
                Repeater {
                    model: section.modelData.keybinds
                    delegate: Rectangle {
                        id: bindRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: Appearance.rounding.small
                        color: rowHover.hovered ? Appearance.m3colors.m3surfaceContainerHigh : "transparent"
                        HoverHandler {
                            id: rowHover
                        }
                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 10
                                rightMargin: 8
                            }
                            spacing: 12
                            StyledText {
                                Layout.fillWidth: true
                                text: bindRow.modelData.comment
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            Repeater { // Each combo, "or" between them
                                model: bindRow.modelData.combos
                                delegate: Row {
                                    id: combo
                                    required property var modelData
                                    required property int index
                                    spacing: 4
                                    StyledText {
                                        visible: combo.index > 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        rightPadding: 2
                                        text: Translation.tr("or")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                    Repeater {
                                        model: combo.modelData
                                        delegate: KeyChip {
                                            required property string modelData
                                            key: page.keySubstitutions[modelData] ?? modelData
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
