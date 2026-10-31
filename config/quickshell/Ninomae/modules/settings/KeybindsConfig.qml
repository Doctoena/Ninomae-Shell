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
// Binds come from the `description` in keybinds.lua ("Category: What it does"). Each row's Edit changes its keys
// or turns it off, and Add shortcut adds your own (services/KeybindOverrides.qml, which hands them to Hyprland).
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
    property string editingRow: "" // The bind whose edit buttons are open, by description
    property bool adding: false // The Add a shortcut form is open
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
    // A row's Edit: open its buttons and, when its keys can be changed, start listening for them straight away
    function editRow(row) {
        page.stopCapture();
        page.captureMessage = "";
        page.editingRow = row.description;
        if (page.editable(row)) page.startCapture(row.description);
    }
    function closeRow() {
        page.stopCapture();
        page.captureMessage = "";
        page.editingRow = "";
    }
    function stopCapture() {
        page.previewKeys = [];
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
        const global = b => (b.submap ?? "global") === "global" && b.modmask === mask && b.description !== page.capturing;
        // The workspace keys (Super, Super+Shift, Super+Alt with 1–0) are bound by position, so Hyprland lists
        // them with no key: find them by their description instead
        const workspaceKey = b => /^\d$/.test(key) && (b.key ?? "") === "" && (b.description ?? "").includes("1-10");
        const found = HyprlandKeybinds.raw.find(b => global(b) && ((b.key ?? "").toLowerCase() === key.toLowerCase() || workspaceKey(b)));
        if (!found) return "";
        return (found.description ?? "").replace(/^\[hidden\]\s*/, "") || Translation.tr("another shortcut");
    }
    function pretty(mods, key) { return [...mods.map(m => m === "SUPER" ? "Super" : m === "CTRL" ? "Ctrl" : m === "ALT" ? "Alt" : "Shift"), page.keySubstitutions[key] ?? key].join("+"); }
    // What's held down while recording, as the key chips show it, so you see the shortcut build up
    property var previewKeys: []
    function updatePreview(event, released) {
        const m = event.modifiers, k = event.key;
        let held = { Super: !!(m & Qt.MetaModifier), Ctrl: !!(m & Qt.ControlModifier),
                     Alt: !!(m & Qt.AltModifier), Shift: !!(m & Qt.ShiftModifier) };
        // A modifier's own press or release: its event carries the state from before it
        if (k === Qt.Key_Meta || k === Qt.Key_Super_L || k === Qt.Key_Super_R) held.Super = !released;
        else if (k === Qt.Key_Control) held.Ctrl = !released;
        else if (k === Qt.Key_Alt || k === Qt.Key_AltGr) held.Alt = !released;
        else if (k === Qt.Key_Shift) held.Shift = !released;
        const keys = Object.keys(held).filter(name => held[name]);
        const name = released ? "" : page.keyName(k);
        page.previewKeys = name ? [...keys, name] : keys;
    }
    function handleKey(event) {
        event.accepted = true;
        page.updatePreview(event, false);
        if (event.key === Qt.Key_Escape) { page.stopCapture(); page.captureMessage = ""; page.editingRow = ""; return; }
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
        page.editingRow = "";
        if (what === "add") {
            KeybindOverrides.addShortcut(page.newName.trim() || page.newCommand.trim(), page.newCommand.trim(), combo);
            page.newName = ""; page.newCommand = "";
            page.adding = false;
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
        Keys.onReleased: event => { event.accepted = true; if (page.capturing !== "") page.updatePreview(event, true); }
    }
    // While recording: the keys held so far, or what to do when none are
    component KeyPreview: Row {
        spacing: 4
        StyledText {
            visible: page.previewKeys.length === 0
            anchors.verticalCenter: parent.verticalCenter
            text: Translation.tr("Press the new shortcut. Esc cancels.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colPrimary
        }
        Repeater {
            model: page.previewKeys
            delegate: KeyChip {
                required property string modelData
                key: page.keySubstitutions[modelData] ?? modelData
            }
        }
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

    // Search pill, and Add shortcut
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
            materialIcon: page.adding ? "close" : "add"
            mainText: page.adding ? Translation.tr("Cancel") : Translation.tr("Add shortcut")
            onClicked: { page.closeRow(); page.adding = !page.adding; }
        }
    }

    // ── Add a shortcut ──
    ContentSection {
        visible: page.adding
        icon: "add"
        title: Translation.tr("Add a shortcut")
        spacing: 10
        ColumnLayout {
            Layout.fillWidth: true
            SettingRow {
                icon: "label"
                text: Translation.tr("Name")
                StyledTextArea {
                    Layout.preferredWidth: 300
                    text: page.newName
                    onTextChanged: if (text !== page.newName) page.newName = text.replace(/\n/g, "")
                }
            }
            SettingRow {
                icon: "terminal"
                text: Translation.tr("Command")
                tooltip: Translation.tr("What runs, like zen-browser or kitty -e btop")
                StyledTextArea {
                    Layout.preferredWidth: 300
                    text: page.newCommand
                    onTextChanged: if (text !== page.newCommand) page.newCommand = text.replace(/\n/g, "")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                KeyPreview {
                    Layout.fillWidth: true
                    visible: page.capturing === "add"
                }
                Item { Layout.fillWidth: page.capturing !== "add" }
                RippleButtonWithIcon {
                    enabled: page.newCommand.trim() !== "" && page.capturing === ""
                    opacity: enabled ? 1 : 0.5
                    materialIcon: "keyboard"
                    mainText: Translation.tr("Record the keys")
                    onClicked: { page.closeRow(); page.startCapture("add"); }
                }
            }
        }
    }

    // ── Turned off: shown while there are any, to turn them back on ──
    ContentSection {
        visible: Object.keys(KeybindOverrides.changed).some(d => KeybindOverrides.changed[d] === false)
        icon: "block"
        title: Translation.tr("Turned off")
        spacing: 10
        ColumnLayout {
            Layout.fillWidth: true
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

    StyledText { // Why a recorded shortcut wasn't taken (a row shows its own under it)
        Layout.fillWidth: true
        Layout.leftMargin: 4
        visible: page.captureMessage !== "" && page.editingRow === ""
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
                        readonly property bool editing: page.editingRow === modelData.description
                        readonly property bool recording: page.capturing !== "" && page.capturing === modelData.description
                        readonly property bool custom: page.isCustom(modelData.description)
                        Layout.fillWidth: true
                        implicitHeight: 40 + (rowMessage.visible ? rowMessage.implicitHeight + 8 : 0)
                        radius: Appearance.rounding.small
                        color: rowHover.hovered || editing ? Appearance.m3colors.m3surfaceContainerHigh : "transparent"
                        HoverHandler {
                            id: rowHover
                        }
                        StyledText { // Why the keys pressed weren't taken
                            id: rowMessage
                            anchors {
                                left: parent.left
                                right: parent.right
                                bottom: parent.bottom
                                leftMargin: 10
                                rightMargin: 8
                                bottomMargin: 8
                            }
                            visible: bindRow.editing && page.captureMessage !== ""
                            wrapMode: Text.Wrap
                            text: page.captureMessage
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colError
                        }
                        RowLayout {
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                leftMargin: 10
                                rightMargin: 8
                            }
                            height: 40
                            spacing: 12
                            StyledText {
                                Layout.fillWidth: true
                                text: bindRow.modelData.comment
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            KeyPreview { // Recording this one
                                visible: bindRow.recording
                            }
                            Repeater { // Each combo, "or" between them
                                model: bindRow.modelData.combos
                                delegate: Row {
                                    id: combo
                                    required property var modelData
                                    required property int index
                                    visible: !bindRow.recording
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
                            // Edit starts listening for the new keys at once, with this row's other buttons beside
                            // it: turn it off (or remove your own), put it back, close
                            IconAction { // Listen again (recording stops by itself after 20 s)
                                visible: bindRow.editing && !bindRow.recording && page.editable(bindRow.modelData)
                                symbol: "keyboard"
                                tip: Translation.tr("Change the keys")
                                onClicked: page.startCapture(bindRow.modelData.description)
                            }
                            IconAction {
                                visible: bindRow.editing && !bindRow.custom
                                symbol: "block"
                                tip: Translation.tr("Turn off")
                                onClicked: { page.closeRow(); KeybindOverrides.turnOff(bindRow.modelData.description); }
                            }
                            IconAction {
                                visible: bindRow.editing && bindRow.custom
                                symbol: "delete"
                                tip: Translation.tr("Remove")
                                onClicked: { page.closeRow(); KeybindOverrides.removeShortcut(page.customIndex(bindRow.modelData.description)); }
                            }
                            IconAction {
                                visible: bindRow.editing && KeybindOverrides.changed[bindRow.modelData.description] !== undefined
                                symbol: "undo"
                                tip: Translation.tr("Back to the original keys")
                                onClicked: { page.closeRow(); KeybindOverrides.reset(bindRow.modelData.description); }
                            }
                            IconAction { // Edit, or Close while open. Kept in place on every row, so they line up
                                opacity: page.fixed(bindRow.modelData.description) ? 0 : 1
                                enabled: !page.fixed(bindRow.modelData.description)
                                symbol: bindRow.editing ? "close" : "edit"
                                tip: bindRow.editing ? Translation.tr("Close") : Translation.tr("Edit")
                                onClicked: bindRow.editing ? page.closeRow() : page.editRow(bindRow.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
