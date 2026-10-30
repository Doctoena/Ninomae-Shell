pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
// Keybinds (formerly the cheatsheet overlay): one card per category, read live from Hyprland.
// Binds come from the `description` in keybinds.lua ("Category: What it does"). Edit changes their keys, turns
// them off or adds your own (services/KeybindOverrides.qml, which hands them to Hyprland).
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
                    else merged.push({ comment: bind.comment, description: bind.description, combos: [keys] });
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


    // ── Editing ──
    property bool editMode: false
    // What's being recorded: a bind's description, "add" for a new shortcut, or "" for nothing
    property string capturing: ""
    property string captureMessage: ""
    property string newName: ""
    property string newCommand: ""
    // A row can be changed when it's one shortcut of letters and modifiers (not the 1–0 rows or mouse binds)
    function editable(row) {
        if (row.combos.length !== 1 || page.fixed(row.description)) return false;
        const key = row.combos[0][row.combos[0].length - 1] ?? "";
        return !/^(code:|mouse)/.test(key) && key !== "1–0";
    }
    function isCustom(description) { return (description ?? "").startsWith("Custom: "); }
    // Set somewhere else, so no edit buttons here: the clip key is in Settings → Games
    function fixed(description) { return description === "Shell: Save gameplay clip (while a game runs)"; }
    function customIndex(description) {
        const name = description.substring("Custom: ".length);
        return KeybindOverrides.added.findIndex(b => (b.name || b.command) === name);
    }
    function startCapture(what) {
        page.capturing = what;
        page.captureMessage = "";
        KeybindOverrides.startCapture();
        captureArea.forceActiveFocus();
        captureTimeout.restart();
    }
    function stopCapture() {
        if (page.capturing === "") return;
        page.capturing = "";
        captureTimeout.stop();
        KeybindOverrides.stopCapture();
    }
    Timer { id: captureTimeout; interval: 20000; onTriggered: page.stopCapture() } // Never leave Hyprland without its binds
    Component.onDestruction: page.stopCapture()

    // Qt's key → the name Hyprland uses. Letters and digits as they are, the rest by name
    readonly property var keyNames: ({
        [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "KP_Enter", [Qt.Key_Tab]: "Tab", [Qt.Key_Backspace]: "BackSpace",
        [Qt.Key_Delete]: "Delete", [Qt.Key_Insert]: "Insert", [Qt.Key_Home]: "Home", [Qt.Key_End]: "End",
        [Qt.Key_PageUp]: "Prior", [Qt.Key_PageDown]: "Next", [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right",
        [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down", [Qt.Key_Space]: "Space", [Qt.Key_Print]: "Print",
        [Qt.Key_Slash]: "Slash", [Qt.Key_Period]: "Period", [Qt.Key_Comma]: "Comma", [Qt.Key_Semicolon]: "Semicolon",
        [Qt.Key_Apostrophe]: "Apostrophe", [Qt.Key_Minus]: "Minus", [Qt.Key_Equal]: "Equal",
        [Qt.Key_BracketLeft]: "BracketLeft", [Qt.Key_BracketRight]: "BracketRight", [Qt.Key_Backslash]: "Backslash",
        [Qt.Key_QuoteLeft]: "grave",
        // Shift turns a digit into its symbol: back to the digit
        [Qt.Key_Exclam]: "1", [Qt.Key_At]: "2", [Qt.Key_NumberSign]: "3", [Qt.Key_Dollar]: "4", [Qt.Key_Percent]: "5",
        [Qt.Key_AsciiCircum]: "6", [Qt.Key_Ampersand]: "7", [Qt.Key_Asterisk]: "8", [Qt.Key_ParenLeft]: "9", [Qt.Key_ParenRight]: "0"
    })
    function keyName(key) {
        if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key);
        if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key);
        if (key >= Qt.Key_F1 && key <= Qt.Key_F24) return "F" + (key - Qt.Key_F1 + 1);
        return page.keyNames[key] ?? "";
    }
    // The bind already on these keys, if any (not the one being changed)
    function clash(mods, key) {
        const mask = (mods.includes("SUPER") ? 64 : 0) | (mods.includes("CTRL") ? 4 : 0) | (mods.includes("ALT") ? 8 : 0) | (mods.includes("SHIFT") ? 1 : 0);
        const found = HyprlandKeybinds.raw.find(b => (b.submap ?? "global") === "global" && b.modmask === mask
            && (b.key ?? "").toLowerCase() === key.toLowerCase() && b.description !== page.capturing);
        if (!found) return "";
        return (found.description ?? "").replace(/^\[hidden\]\s*/, "") || Translation.tr("another shortcut");
    }
    function pretty(mods, key) { return [...mods.map(m => m === "SUPER" ? "Super" : m === "CTRL" ? "Ctrl" : m === "ALT" ? "Alt" : "Shift"), page.keySubstitutions[key] ?? key].join("+"); }
    function handleKey(event) {
        event.accepted = true;
        if (event.key === Qt.Key_Escape) { page.stopCapture(); page.captureMessage = ""; return; }
        const key = page.keyName(event.key);
        if (key === "") return; // A modifier on its own: wait for the key
        const mods = [];
        if (event.modifiers & Qt.MetaModifier) mods.push("SUPER");
        if (event.modifiers & Qt.ControlModifier) mods.push("CTRL");
        if (event.modifiers & Qt.AltModifier) mods.push("ALT");
        if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT");
        if (!mods.some(m => m !== "SHIFT") && !/^(F\d+|Print)$/.test(key)) {
            page.captureMessage = Translation.tr("Hold Super, Ctrl or Alt with the key, so it doesn't go off while you type.");
            return;
        }
        const taken = page.clash(mods, key);
        if (taken !== "") {
            page.captureMessage = Translation.tr("%1 already does “%2”. Try another, or turn that one off first.").arg(page.pretty(mods, key)).arg(taken);
            return;
        }
        const combo = [...mods, key].join(" + ");
        const what = page.capturing;
        page.stopCapture();
        page.captureMessage = "";
        if (what === "add") {
            KeybindOverrides.addShortcut(page.newName.trim() || page.newCommand.trim(), page.newCommand.trim(), combo);
            page.newName = ""; page.newCommand = "";
        } else if (page.isCustom(what)) {
            KeybindOverrides.setShortcutKeys(page.customIndex(what), combo);
        } else {
            KeybindOverrides.setKeys(what, combo);
        }
    }
    Item { // Takes the keys while recording
        id: captureArea
        Layout.preferredHeight: 0
        Keys.onPressed: event => page.handleKey(event)
    }
    component IconAction: RippleButton {
        id: iconAction
        property string symbol
        property string tip
        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.small
        colBackground: "transparent"
        colBackgroundHover: Appearance.m3colors.m3surfaceContainerHighest
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: iconAction.symbol
            iconSize: 18
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledToolTip { text: iconAction.tip }
    }

    // Search pill, and Edit
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
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

        RippleButtonWithIcon {
            implicitHeight: 44
            materialIcon: page.editMode ? "check" : "edit"
            mainText: page.editMode ? Translation.tr("Done") : Translation.tr("Edit")
            onClicked: { page.stopCapture(); page.captureMessage = ""; page.editMode = !page.editMode; }
        }
    }

    // ── Your changes: add a shortcut, the ones turned off ──
    ContentSection {
        visible: page.editMode
        icon: "edit_note"
        title: Translation.tr("Your changes")
        spacing: 10
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("Change a shortcut's keys or turn it off with the buttons on its row. Hyprland picks up each change straight away.")
        }
        ContentSubsection {
            Layout.fillWidth: true
            title: Translation.tr("Add a shortcut")
            SettingRow {
                icon: "label"
                text: Translation.tr("Name")
                MaterialTextArea {
                    Layout.preferredWidth: 300
                    text: page.newName
                    onTextChanged: if (text !== page.newName) page.newName = text.replace(/\n/g, "")
                }
            }
            SettingRow {
                icon: "terminal"
                text: Translation.tr("Command")
                tooltip: Translation.tr("What runs, like zen-browser or kitty -e btop")
                MaterialTextArea {
                    Layout.preferredWidth: 300
                    text: page.newCommand
                    onTextChanged: if (text !== page.newCommand) page.newCommand = text.replace(/\n/g, "")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    visible: page.capturing === "add"
                    text: Translation.tr("Press the new shortcut. Esc cancels.")
                    color: Appearance.colors.colPrimary
                }
                Item { Layout.fillWidth: page.capturing !== "add" }
                RippleButtonWithIcon {
                    enabled: page.newCommand.trim() !== "" && page.capturing === ""
                    opacity: enabled ? 1 : 0.5
                    materialIcon: "keyboard"
                    mainText: Translation.tr("Record the keys")
                    onClicked: page.startCapture("add")
                }
            }
        }
        ContentSubsection {
            Layout.fillWidth: true
            visible: Object.keys(KeybindOverrides.changed).some(d => KeybindOverrides.changed[d] === false)
            title: Translation.tr("Turned off")
            Repeater {
                model: Object.keys(KeybindOverrides.changed).filter(d => KeybindOverrides.changed[d] === false)
                delegate: RowLayout {
                    id: offRow
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    StyledText {
                        Layout.fillWidth: true
                        text: offRow.modelData.replace(": ", " · ")
                        color: Appearance.colors.colOnLayer1
                    }
                    RippleButtonWithIcon {
                        materialIcon: "undo"
                        mainText: Translation.tr("Turn back on")
                        onClicked: KeybindOverrides.reset(offRow.modelData)
                    }
                }
            }
        }
    }

    StyledText { // Why a recorded shortcut wasn't taken
        Layout.fillWidth: true
        Layout.leftMargin: 4
        visible: page.captureMessage !== ""
        wrapMode: Text.Wrap
        text: page.captureMessage
        color: Appearance.colors.colError
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
                            StyledText { // Recording this one
                                visible: page.capturing !== "" && page.capturing === bindRow.modelData.description
                                text: Translation.tr("Press the new shortcut. Esc cancels.")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colPrimary
                            }
                            Repeater { // Each combo, "or" between them
                                model: bindRow.modelData.combos
                                delegate: Row {
                                    id: combo
                                    required property var modelData
                                    required property int index
                                    visible: page.capturing === "" || page.capturing !== bindRow.modelData.description
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
                            // Editing: change the keys, turn it off (or remove your own), put it back
                            IconAction {
                                visible: page.editMode && page.editable(bindRow.modelData) && page.capturing === ""
                                symbol: "edit"
                                tip: Translation.tr("Change the keys")
                                onClicked: page.startCapture(bindRow.modelData.description)
                            }
                            IconAction {
                                visible: page.editMode && page.capturing === "" && !page.isCustom(bindRow.modelData.description) && !page.fixed(bindRow.modelData.description)
                                symbol: "block"
                                tip: Translation.tr("Turn off")
                                onClicked: KeybindOverrides.turnOff(bindRow.modelData.description)
                            }
                            IconAction {
                                visible: page.editMode && page.capturing === "" && page.isCustom(bindRow.modelData.description)
                                symbol: "delete"
                                tip: Translation.tr("Remove")
                                onClicked: KeybindOverrides.removeShortcut(page.customIndex(bindRow.modelData.description))
                            }
                            IconAction {
                                visible: page.editMode && page.capturing === "" && KeybindOverrides.changed[bindRow.modelData.description] !== undefined
                                symbol: "undo"
                                tip: Translation.tr("Back to the original keys")
                                onClicked: KeybindOverrides.reset(bindRow.modelData.description)
                            }
                        }
                    }
                }
            }
        }
    }
}
