pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
// Window rules: every rule Hyprland applies to windows, shipped ones included (services/WindowRules.qml saves
// them and hands them to Hyprland). A rule matches apps (or titles, or other window states) and sets how their
// windows open and look. Fields Settings has no control for are kept as they are.
ContentPage {
    id: page
    Component.onCompleted: HyprlandData.updateAll() // The open apps, for the app search

    // ── Apps ──
    // The installed apps load a moment after the page: names and icons are worked out again once they're there
    readonly property int appsLoaded: DesktopEntries.applications.values.length
    function appName(cls) { page.appsLoaded; return DesktopEntries.heuristicLookup(cls)?.name ?? cls; }
    function appIcon(cls) { return Quickshell.iconPath(AppSearch.guessIcon(cls), "application-x-executable"); }
    // A class pattern that's just a list of apps, "^(kitty|org\.gnome\.Nautilus)$", as that list. Else null
    function classList(pattern) {
        if (!pattern) return [];
        const m = /^\^\((.*)\)\$$/.exec(pattern) ?? /^\^(.*)\$$/.exec(pattern);
        if (!m) return null;
        const alts = [];
        let current = "";
        for (let i = 0; i < m[1].length; i++) {
            const ch = m[1][i];
            if (ch === "\\") { current += m[1][i + 1] ?? ""; i++; continue; } // An escaped character is itself
            if (ch === "|") { alts.push(current); current = ""; continue; }
            if ("()*+?[]{}^$.".includes(ch)) return null; // Regex-like (groups, wildcards): a pattern, not names
            current += ch;
        }
        alts.push(current);
        return alts.some(a => a === "") ? null : alts;
    }
    function classPattern(list) { return list.length === 0 ? "" : "^(" + list.map(c => c.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|") + ")$"; }
    // A pattern as words: "^(Open File|Save As)(.*)$" → "Open File, Save As…"
    function readable(pattern) {
        return String(pattern ?? "").replace(/^\^/, "").replace(/\$$/, "").replace(/\(\.\*\)|\.\*/g, "…")
            .replace(/^\((.*?)\)/, "$1").replace(/\\(.)/g, "$1").replace(/\|/g, ", ");
    }

    // ── Describing a rule ──
    function target(rule) {
        page.appsLoaded;
        const m = rule?.match ?? {};
        const parts = [];
        const apps = page.classList(m.class);
        if (apps && apps.length > 0) parts.push(apps.length <= 3 ? apps.map(page.appName).join(", ")
            : Translation.tr("%1 and %2 more").arg(apps.slice(0, 2).map(page.appName).join(", ")).arg(apps.length - 2));
        else if (m.class) parts.push(m.class === ".*" ? Translation.tr("every app") : Translation.tr("apps like “%1”").arg(page.readable(m.class)));
        if (m.title) parts.push(Translation.tr("titled “%1”").arg(page.readable(m.title)));
        if (m.xwayland === true) parts.push(Translation.tr("XWayland windows"));
        if (m.float === true) parts.push(Translation.tr("floating windows"));
        if (m.float === false) parts.push(Translation.tr("tiled windows"));
        const text = parts.join(", ");
        return text === "" ? (rule?.name ?? "") : text.charAt(0).toUpperCase() + text.slice(1);
    }
    function opacityParts(value) {
        const nums = String(value ?? "").split(/\s+/).filter(t => /^[\d.]+$/.test(t)).map(Number);
        return [nums[0] ?? 1, nums[1] ?? nums[0] ?? 1];
    }
    function summary(rule) {
        const e = rule.effects ?? {};
        const out = [];
        if (e.float) out.push(Translation.tr("Floats"));
        if (e.center) out.push(Translation.tr("Centred"));
        if (e.size) out.push(Translation.tr("Size %1").arg(e.size));
        if (e.move) out.push(/^9{5}/.test(e.move) ? Translation.tr("Off screen") : Translation.tr("At %1").arg(e.move));
        if (e.pin) out.push(Translation.tr("On every workspace"));
        if (e.workspace) out.push(Translation.tr("Workspace %1").arg(String(e.workspace).replace(" silent", "")));
        if (e.maximize) out.push(Translation.tr("Maximised"));
        if (e.fullscreen) out.push(Translation.tr("Fullscreen"));
        if (e.opacity) {
            const [a, b] = page.opacityParts(e.opacity);
            out.push(a === b ? Translation.tr("%1% opaque").arg(Math.round(a * 100))
                             : Translation.tr("%1% / %2% opaque").arg(Math.round(a * 100)).arg(Math.round(b * 100)));
        }
        if (e.no_blur) out.push(Translation.tr("No blur"));
        if (e.no_shadow) out.push(Translation.tr("No shadow"));
        if (e.rounding === 0) out.push(Translation.tr("Square corners"));
        if (e.no_anim) out.push(Translation.tr("No animations"));
        if (e.keep_aspect_ratio) out.push(Translation.tr("Keeps its shape"));
        if (e.no_initial_focus) out.push(Translation.tr("Doesn't take focus"));
        if (e.idle_inhibit && e.idle_inhibit !== "none") out.push(Translation.tr("Keeps the screen awake"));
        if (e.immediate) out.push(Translation.tr("Allows tearing"));
        return out.join(" · ");
    }

    // ── The list, searchable ──
    property string query: ""
    readonly property var shown: {
        const q = page.query.trim().toLowerCase();
        return WindowRules.rules.map((rule, index) => ({ rule: rule, index: index })).filter(item => q === ""
            || [item.rule.name, item.rule.note, page.target(item.rule), page.summary(item.rule), item.rule.match?.class, item.rule.match?.title]
                .some(t => String(t ?? "").toLowerCase().includes(q)));
    }
    // Built-in fixes (behind-the-scenes rules the setup relies on) sit folded under the app rules
    readonly property var shownApps: page.shown.filter(item => !item.rule.builtin)
    readonly property var shownBuiltin: page.shown.filter(item => item.rule.builtin)
    property bool builtinOpen: false

    // ── Editing: a copy of the rule, saved back as a whole ──
    property int editing: -2 // -2 none, -1 a new rule, else its index
    property string editingName: "" // The rule being edited: followed by name, as other changes move it in the list
    property var form: ({})
    Connections {
        target: WindowRules
        function onRulesChanged() {
            if (page.editing < 0) return;
            const index = WindowRules.rules.findIndex(r => r.name === page.editingName);
            page.editing = index >= 0 ? index : -2; // Removed: close the editor
        }
    }
    function edit(index) {
        page.editingName = index >= 0 ? (WindowRules.rules[index]?.name ?? "") : "";
        const r = index >= 0 ? WindowRules.rules[index]
                             : { name: "", note: "", enabled: true, match: {}, effects: { float: true, center: true } };
        page.form = JSON.parse(JSON.stringify(r));
        page.editing = -2; // The editor is made afresh, so its controls start from the form
        Qt.callLater(() => page.editing = index);
    }
    function setMatch(key, value) {
        const m = Object.assign({}, page.form.match);
        if (value === undefined || value === "") delete m[key]; else m[key] = value;
        page.form = Object.assign({}, page.form, { match: m });
    }
    function setEffect(key, value) {
        const e = Object.assign({}, page.form.effects);
        if (value === undefined || value === "" || value === false) delete e[key]; else e[key] = value;
        page.form = Object.assign({}, page.form, { effects: e });
    }
    readonly property bool formValid: Object.keys(page.form.match ?? {}).length > 0 && Object.keys(page.form.effects ?? {}).length > 0
    function saveForm() {
        const rule = JSON.parse(JSON.stringify(page.form));
        if (!rule.name) { // A name Hyprland can tell apart: from the first app, else "rule"
            const apps = page.classList(rule.match.class) ?? [];
            const base = (apps[0] ?? "rule").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "rule";
            let name = base, n = 2;
            while (WindowRules.rules.some(r => r.name === name)) name = `${base}-${n++}`;
            rule.name = name;
        }
        if (page.editing >= 0) WindowRules.replace(page.editing, rule);
        else WindowRules.add(rule);
        page.editing = -2;
    }

    component SearchPill: Rectangle {
        id: pill
        property alias text: field.text
        property string placeholder
        Layout.fillWidth: true
        implicitHeight: 44
        radius: Appearance.rounding.container
        color: Appearance.m3colors.m3surfaceContainer
        border.width: field.activeFocus ? 2 : 0
        border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45)
        MaterialSymbol {
            id: pillIcon
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: "search"
            iconSize: 20
            color: Appearance.colors.colPrimary
        }
        TextField {
            id: field
            anchors { left: pillIcon.right; leftMargin: 8; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            background: null
            padding: 0
            color: Appearance.colors.colOnLayer1
            placeholderText: pill.placeholder
            placeholderTextColor: Appearance.colors.colSubtext
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.small
            selectionColor: Appearance.colors.colSecondaryContainer
        }
    }

    component RuleRow: Rectangle {
        id: ruleRow
        required property var modelData
        readonly property var rule: modelData.rule
        readonly property int ruleIndex: modelData.index
        readonly property var apps: page.classList(rule.match?.class) ?? []
        Layout.fillWidth: true
        implicitHeight: ruleContent.implicitHeight + 16
        radius: Appearance.rounding.small
        color: rowHover.hovered ? Appearance.m3colors.m3surfaceContainerHigh : "transparent"
        HoverHandler { id: rowHover }
        RowLayout {
            id: ruleContent
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 8 }
            spacing: 12
            opacity: ruleRow.rule.enabled === false ? 0.55 : 1
            Item { // Up to three app icons, else what it matches by
                implicitWidth: 40
                implicitHeight: 32
                Repeater {
                    model: ruleRow.apps.slice(0, 3)
                    delegate: IconImage {
                        required property string modelData
                        required property int index
                        x: index * 8
                        y: index * 2
                        implicitSize: ruleRow.apps.length > 1 ? 24 : 28
                        source: page.appIcon(modelData)
                    }
                }
                MaterialSymbol {
                    visible: ruleRow.apps.length === 0
                    anchors.centerIn: parent
                    text: ruleRow.rule.match?.title ? "title" : "select_window"
                    iconSize: 22
                    color: Appearance.colors.colPrimary
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: page.target(ruleRow.rule)
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: page.summary(ruleRow.rule)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: (ruleRow.rule.note ?? "") !== ""
                    wrapMode: Text.Wrap
                    text: ruleRow.rule.note ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            StyledSwitch {
                scale: 0.8
                checked: ruleRow.rule.enabled !== false
                onClicked: WindowRules.setEnabled(ruleRow.ruleIndex, checked)
                StyledToolTip { text: Translation.tr("Turn the rule on or off without removing it") }
            }
            RippleButtonWithIcon { // A shipped rule you edited: back to how it ships
                visible: WindowRules.isEdited(ruleRow.ruleIndex)
                materialIcon: "undo"
                mainText: Translation.tr("Reset")
                onClicked: { if (page.editing === ruleRow.ruleIndex) page.editing = -2; WindowRules.restore(ruleRow.ruleIndex); }
                StyledToolTip { text: Translation.tr("Back to the rule as it ships") }
            }
            RippleButtonWithIcon {
                materialIcon: "edit"
                mainText: Translation.tr("Edit")
                onClicked: page.edit(ruleRow.ruleIndex)
            }
            RippleButtonWithIcon {
                materialIcon: "delete"
                mainText: Translation.tr("Remove")
                onClicked: WindowRules.remove(ruleRow.ruleIndex) // An editor open on it closes (onRulesChanged)
            }
        }
    }

    // ── Search and add ──
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        SearchPill {
            placeholder: Translation.tr("Search rules")
            onTextChanged: page.query = text
        }
        RippleButtonWithIcon {
            implicitHeight: 44
            enabled: page.editing === -2
            opacity: enabled ? 1 : 0.5
            materialIcon: "add"
            mainText: Translation.tr("Add a rule")
            onClicked: page.edit(-1)
        }
    }

    // ── The editor (above the list while it's open) ──
    Loader {
        Layout.fillWidth: true
        active: page.editing !== -2
        visible: active
        sourceComponent: ContentSection {
            id: editor
            icon: page.editing >= 0 ? "edit" : "add"
            title: page.editing >= 0 ? Translation.tr("Edit: %1").arg(page.target(WindowRules.rules[page.editing])) : Translation.tr("New rule")
            spacing: 10
            readonly property var apps: page.classList(page.form.match?.class)
            property string appQuery: ""
            // More options: open from the start when the rule already uses one of them, or matches by a pattern
            property bool more: false
            Component.onCompleted: {
                const e = page.form.effects ?? {};
                const extra = ["move", "pin", "maximize", "fullscreen", "no_blur", "no_shadow", "rounding", "no_anim",
                               "keep_aspect_ratio", "no_initial_focus", "immediate", "idle_inhibit"];
                editor.more = extra.some(k => e[k] !== undefined) || editor.apps === null || !!page.form.match?.title;
            }
            // Open windows and installed apps matching the search, by window class
            readonly property var results: {
                const q = editor.appQuery.trim().toLowerCase();
                if (q.length === 0) return [];
                const open = (HyprlandData.windowList ?? []).map(w => w.class).filter(c => c && c !== "org.quickshell");
                const installed = DesktopEntries.applications.values.filter(e => !e.noDisplay).map(e => e.startupClass || e.id).filter(c => c);
                return [...new Set(open.concat(installed))].filter(c => (page.appName(c) + " " + c).toLowerCase().includes(q)).slice(0, 8);
            }

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Applies to")
                Flow { // The apps it applies to: click one to take it off
                    Layout.fillWidth: true
                    spacing: 6
                    visible: (editor.apps ?? []).length > 0
                    Repeater {
                        model: editor.apps ?? []
                        delegate: RippleButton {
                            id: chosenChip
                            required property string modelData
                            implicitHeight: 36
                            implicitWidth: chosenRow.implicitWidth + 24
                            buttonRadius: Appearance.rounding.small
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            onClicked: page.setMatch("class", page.classPattern(editor.apps.filter(a => a !== chosenChip.modelData)))
                            contentItem: RowLayout {
                                id: chosenRow
                                spacing: 8
                                IconImage { implicitSize: 20; source: page.appIcon(chosenChip.modelData) }
                                StyledText { text: page.appName(chosenChip.modelData); color: Appearance.colors.colOnSecondaryContainer }
                                MaterialSymbol { text: "close"; iconSize: 16; color: Appearance.colors.colOnSecondaryContainer }
                            }
                            StyledToolTip { text: Translation.tr("Take off %1 (window class %2)").arg(page.appName(chosenChip.modelData)).arg(chosenChip.modelData) }
                        }
                    }
                }
                StyledText { // A class pattern that isn't a plain list: edited under Advanced
                    visible: editor.apps === null
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    wrapMode: Text.Wrap
                    text: Translation.tr("This rule matches apps by a pattern (%1). Change it under More options → Advanced.").arg(page.form.match?.class ?? "")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                SearchPill { // Find an app to add
                    visible: editor.apps !== null
                    placeholder: Translation.tr("Search apps to add")
                    onTextChanged: editor.appQuery = text
                }
                Repeater {
                    model: editor.results
                    delegate: RippleButton {
                        id: resultRow
                        required property string modelData
                        readonly property bool added: (editor.apps ?? []).includes(modelData)
                        Layout.fillWidth: true
                        implicitHeight: 44
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
                        onClicked: if (!added) page.setMatch("class", page.classPattern((editor.apps ?? []).concat([modelData])))
                        contentItem: RowLayout {
                            spacing: 12
                            IconImage { implicitSize: 28; source: page.appIcon(resultRow.modelData) }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText { text: page.appName(resultRow.modelData); color: Appearance.colors.colOnLayer1 }
                                StyledText { text: resultRow.modelData; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                            }
                            MaterialSymbol { text: resultRow.added ? "check" : "add"; iconSize: 20; color: Appearance.colors.colPrimary }
                        }
                    }
                }
                StyledText {
                    visible: editor.appQuery.trim() !== "" && editor.results.length === 0
                    Layout.leftMargin: 4
                    text: Translation.tr("No apps match. You can type a window class under More options → Advanced.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                StyledText { // Conditions there's no control for: kept, and said
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    visible: text !== ""
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    text: {
                        const m = page.form.match ?? {};
                        const extra = [];
                        if (m.xwayland === true) extra.push(Translation.tr("XWayland windows"));
                        if (m.float === true) extra.push(Translation.tr("floating windows"));
                        if (m.float === false) extra.push(Translation.tr("tiled windows"));
                        return extra.length ? Translation.tr("Only %1.").arg(extra.join(Translation.tr(" and "))) : "";
                    }
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Placement")
                ConfigSwitch {
                    buttonIcon: "picture_in_picture"
                    text: Translation.tr("Floating")
                    checked: !!page.form.effects?.float
                    onCheckedChanged: page.setEffect("float", checked)
                }
                ConfigSwitch {
                    buttonIcon: "center_focus_strong"
                    text: Translation.tr("Centred")
                    checked: !!page.form.effects?.center
                    onCheckedChanged: page.setEffect("center", checked)
                }
                SettingRow {
                    icon: "aspect_ratio"
                    text: Translation.tr("Size")
                    tooltip: Translation.tr("Width and height, in % of the screen or pixels, like 60% 65%. For floating windows")
                    StyledTextArea {
                        Layout.preferredWidth: 160
                        text: page.form.effects?.size ?? ""
                        onTextChanged: if (text !== (page.form.effects?.size ?? "")) page.setEffect("size", text.replace(/\n/g, "").trim())
                    }
                }
                SettingRow {
                    visible: editor.more
                    icon: "open_with"
                    text: Translation.tr("Position")
                    tooltip: Translation.tr("Left and top, in % of the screen or pixels, like 73% 72%. For floating windows")
                    StyledTextArea {
                        Layout.preferredWidth: 160
                        text: page.form.effects?.move ?? ""
                        onTextChanged: if (text !== (page.form.effects?.move ?? "")) page.setEffect("move", text.replace(/\n/g, "").trim())
                    }
                }
                ConfigSwitch {
                    visible: editor.more
                    buttonIcon: "push_pin"
                    text: Translation.tr("On every workspace")
                    checked: !!page.form.effects?.pin
                    onCheckedChanged: page.setEffect("pin", checked)
                }
                ConfigSwitch {
                    visible: editor.more
                    buttonIcon: "crop_free"
                    text: Translation.tr("Maximised")
                    checked: !!page.form.effects?.maximize
                    onCheckedChanged: page.setEffect("maximize", checked)
                }
                ConfigSwitch {
                    visible: editor.more
                    buttonIcon: "fullscreen"
                    text: Translation.tr("Fullscreen")
                    checked: !!page.form.effects?.fullscreen
                    onCheckedChanged: page.setEffect("fullscreen", checked)
                }
                ContentSubsectionLabel { text: Translation.tr("Workspace") }
                ConfigSelectionArray {
                    readonly property string current: String(page.form.effects?.workspace ?? "")
                    currentValue: Number(current.split(" ")[0]) || 0
                    onSelected: newValue => page.setEffect("workspace", newValue > 0 ? `${newValue}${current === "" || current.includes("silent") ? " silent" : ""}` : "")
                    options: [{ displayName: Translation.tr("Where it opens"), icon: "open_in_new", value: 0 }]
                        .concat([1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(n => ({ displayName: String(n), value: n })))
                }
                ConfigSwitch {
                    visible: String(page.form.effects?.workspace ?? "") !== ""
                    buttonIcon: "do_not_disturb_on"
                    text: Translation.tr("Stay where I am when it opens")
                    checked: String(page.form.effects?.workspace ?? "").includes("silent")
                    onCheckedChanged: {
                        const n = String(page.form.effects?.workspace ?? "").split(" ")[0];
                        if (n) page.setEffect("workspace", checked ? `${n} silent` : n);
                    }
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Look")
                Repeater { // Opacity, focused and not
                    model: [{ label: Translation.tr("Opacity when focused"), part: 0 }, { label: Translation.tr("Opacity when not focused"), part: 1 }]
                    delegate: RowLayout {
                        id: opacityRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 12
                        MaterialSymbol { Layout.leftMargin: 8; text: "opacity"; iconSize: 20; color: Appearance.colors.colOnSurfaceVariant }
                        StyledText { Layout.preferredWidth: 220; text: opacityRow.modelData.label; color: Appearance.colors.colOnLayer1 }
                        StyledSlider {
                            id: opacitySlider
                            Layout.fillWidth: true
                            configuration: StyledSlider.Configuration.S
                            from: 0.3
                            to: 1
                            stepSize: 0.01
                            value: page.opacityParts(page.form.effects?.opacity)[opacityRow.modelData.part]
                            tooltipContent: `${Math.round(value * 100)}%`
                            onMoved: {
                                const parts = page.opacityParts(page.form.effects?.opacity);
                                parts[opacityRow.modelData.part] = Math.round(value * 100) / 100;
                                page.setEffect("opacity", parts[0] >= 1 && parts[1] >= 1 ? "" : `${parts[0]} override ${parts[1]} override`);
                            }
                        }
                        StyledText {
                            Layout.preferredWidth: 44
                            horizontalAlignment: Text.AlignRight
                            text: `${Math.round(opacitySlider.value * 100)}%`
                            font.family: Appearance.font.family.numbers
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
                ConfigSwitch {
                    visible: editor.more
                    buttonIcon: "blur_off"
                    text: Translation.tr("No blur behind it")
                    checked: !!page.form.effects?.no_blur
                    onCheckedChanged: page.setEffect("no_blur", checked)
                }
                ConfigSwitch {
                    visible: editor.more
                    buttonIcon: "shadow"
                    text: Translation.tr("No shadow")
                    checked: !!page.form.effects?.no_shadow
                    onCheckedChanged: page.setEffect("no_shadow", checked)
                }
                ConfigSwitch {
                    visible: editor.more
                    buttonIcon: "rounded_corner"
                    text: Translation.tr("Square corners")
                    checked: page.form.effects?.rounding === 0
                    onCheckedChanged: page.setEffect("rounding", checked ? 0 : undefined)
                }
                ConfigSwitch {
                    visible: editor.more
                    buttonIcon: "animation"
                    text: Translation.tr("No animations")
                    checked: !!page.form.effects?.no_anim
                    onCheckedChanged: page.setEffect("no_anim", checked)
                }
                ConfigSwitch {
                    visible: editor.more
                    buttonIcon: "fit_screen"
                    text: Translation.tr("Keep its shape when resized")
                    checked: !!page.form.effects?.keep_aspect_ratio
                    onCheckedChanged: page.setEffect("keep_aspect_ratio", checked)
                }
            }

            ContentSubsection {
                visible: editor.more
                Layout.fillWidth: true
                title: Translation.tr("Behaviour")
                ConfigSwitch {
                    buttonIcon: "center_focus_weak"
                    text: Translation.tr("Don't take focus when it opens")
                    checked: !!page.form.effects?.no_initial_focus
                    onCheckedChanged: page.setEffect("no_initial_focus", checked)
                }
                ConfigSwitch {
                    buttonIcon: "speed"
                    text: Translation.tr("Allow tearing (lower input lag in games)")
                    checked: !!page.form.effects?.immediate
                    onCheckedChanged: page.setEffect("immediate", checked)
                }
                ContentSubsectionLabel { text: Translation.tr("Keep the screen awake") }
                ConfigSelectionArray {
                    currentValue: page.form.effects?.idle_inhibit ?? "none"
                    onSelected: newValue => page.setEffect("idle_inhibit", newValue === "none" ? "" : newValue)
                    options: [
                        { displayName: Translation.tr("No"), icon: "bedtime", value: "none" },
                        { displayName: Translation.tr("While focused"), icon: "center_focus_strong", value: "focus" },
                        { displayName: Translation.tr("While fullscreen"), icon: "fullscreen", value: "fullscreen" },
                        { displayName: Translation.tr("While open"), icon: "visibility", value: "always" }
                    ]
                }
            }

            ContentSubsection {
                visible: editor.more
                Layout.fillWidth: true
                title: Translation.tr("Advanced")
                SettingRow {
                    icon: "badge"
                    text: Translation.tr("Window class pattern")
                    tooltip: Translation.tr("A regular expression. The app search fills it in")
                    StyledTextArea {
                        Layout.preferredWidth: 340
                        text: page.form.match?.class ?? ""
                        onTextChanged: if (text !== (page.form.match?.class ?? "")) page.setMatch("class", text.replace(/\n/g, ""))
                    }
                }
                SettingRow {
                    icon: "title"
                    text: Translation.tr("Window title pattern")
                    tooltip: Translation.tr("A regular expression, like ^(Picture-in-Picture)(.*)$ for titles that start that way")
                    StyledTextArea {
                        Layout.preferredWidth: 340
                        text: page.form.match?.title ?? ""
                        onTextChanged: if (text !== (page.form.match?.title ?? "")) page.setMatch("title", text.replace(/\n/g, ""))
                    }
                }
                SettingRow {
                    icon: "sticky_note_2"
                    text: Translation.tr("Note")
                    tooltip: Translation.tr("Why the rule is there, for later")
                    StyledTextArea {
                        Layout.preferredWidth: 340
                        text: page.form.note ?? ""
                        onTextChanged: page.form.note = text.replace(/\n/g, " ")
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                StyledText {
                    Layout.fillWidth: true
                    visible: !page.formValid
                    wrapMode: Text.Wrap
                    text: Object.keys(page.form.match ?? {}).length === 0 ? Translation.tr("Add an app, or a pattern under More options.")
                                                                          : Translation.tr("Turn on at least one thing for it to do.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                RippleButtonWithIcon {
                    materialIcon: editor.more ? "expand_less" : "expand_more"
                    mainText: editor.more ? Translation.tr("Fewer options") : Translation.tr("More options")
                    onClicked: editor.more = !editor.more
                }
                Item { Layout.fillWidth: page.formValid }
                RippleButtonWithIcon {
                    materialIcon: "close"
                    mainText: Translation.tr("Cancel")
                    onClicked: page.editing = -2
                }
                RippleButtonWithIcon {
                    enabled: page.formValid
                    opacity: enabled ? 1 : 0.5
                    materialIcon: "check"
                    mainText: Translation.tr("Save")
                    onClicked: page.saveForm()
                }
            }
        }
    }

    // ── Every rule ──
    ContentSection {
        icon: "select_window"
        title: page.query.trim() === "" ? Translation.tr("Rules (%1)").arg(page.shownApps.length)
                                        : Translation.tr("Rules matching “%1”").arg(page.query.trim())
        spacing: 4
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.bottomMargin: 6
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("How windows open and look, app by app. A change applies to windows opened after you save it. When two rules set the same thing, the lower one wins.")
        }
        Repeater {
            model: page.shownApps
            delegate: RuleRow {}
        }
        RippleButton { // The built-in fixes, folded
            visible: page.shownBuiltin.length > 0
            Layout.fillWidth: true
            Layout.topMargin: 6
            implicitHeight: builtinHeader.implicitHeight + 16
            buttonRadius: Appearance.rounding.small
            colBackground: "transparent"
            colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
            onClicked: page.builtinOpen = !page.builtinOpen
            contentItem: RowLayout {
                id: builtinHeader
                spacing: 12
                MaterialSymbol {
                    Layout.leftMargin: 8
                    text: page.builtinOpen || page.query.trim() !== "" ? "expand_less" : "expand_more"
                    iconSize: 22
                    color: Appearance.colors.colPrimary
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        text: Translation.tr("Built-in fixes (%1)").arg(page.shownBuiltin.length)
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Translation.tr("Small fixes the setup relies on, like no blur behind XWayland menus. Rarely worth changing.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
        Repeater { // Open, or while searching
            model: page.builtinOpen || page.query.trim() !== "" ? page.shownBuiltin : []
            delegate: RuleRow {}
        }
        StyledText {
            visible: page.shown.length === 0
            Layout.leftMargin: 4
            text: page.query.trim() === "" ? Translation.tr("No rules yet.") : Translation.tr("No rules match.")
            color: Appearance.colors.colSubtext
        }
    }
}
