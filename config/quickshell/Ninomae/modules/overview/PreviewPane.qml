import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick.Shapes
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Io

/**
 * Right-hand side of the launcher: a large preview of the selected result
 * (SearchItem), adapting to its kind: app, emoji, math, clipboard text/image, or action.
 * An app's icon glows in its own colour behind it. Its actions ("New Window", a clipboard entry's Copy
 * and Delete) are named rows under the main button; Tab from the list moves into them.
 */
Rectangle {
    id: root
    property Item item // The selected SearchItem
    readonly property bool hasItem: item !== null && item !== undefined
    readonly property bool isApp: hasItem && item.itemType == Translation.tr("App")
    readonly property bool isEmoji: hasItem && item.bigText !== ""
    // Emoji results also carry cliphistRawString, so exclude them here
    readonly property bool isClipboard: hasItem && item.cliphistRawString !== "" && !isEmoji
    readonly property bool isClipboardImage: isClipboard && Cliphist.entryIsImage(item.cliphistRawString)
    readonly property bool isMath: hasItem && item.materialSymbol === "calculate"
    readonly property var actions: hasItem ? (item.itemActions ?? []) : []

    // ── The glow's colour: the most vivid one in the app's icon (the accent for grey icons or no icon) ──
    // Icons are looked up by name in the theme, so their files are found once (a short shell lookup, cached)
    property var iconFiles: ({}) // icon name → its file, or "" when none was found
    readonly property string iconName: (isApp || (hasItem && item.itemIcon !== "" && item.materialSymbol === "")) ? item.itemIcon : ""
    readonly property string iconFile: iconName.startsWith("/") ? iconName : (iconFiles[iconName] ?? "")
    onIconNameChanged: findIcon(iconName)
    function findIcon(name) {
        if (name === "" || name.startsWith("/") || iconFiles[name] !== undefined) return;
        iconFiles = Object.assign({}, iconFiles, { [name]: "" }); // Asked once, even when nothing's found
        iconLookupComp.createObject(root, { name: name }).running = true;
    }
    Component {
        id: iconLookupComp
        Process {
            id: lookup
            required property string name
            // The icon theme and the themes it inherits from first, then hicolor (system, Flatpak, your own) and
            // pixmaps; the name goes in as an argument, never into the script. In this template string a bash \(
            // has to be written \\( (the string would turn \( into a bare bracket, a syntax error for bash)
            command: ["bash", "-c", `n=$1
theme=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
themes=$theme
for t in "$HOME/.local/share/icons/$theme" "/usr/share/icons/$theme"; do # And the themes it inherits from
  [ -f "$t/index.theme" ] && themes="$themes $(sed -n 's/^Inherits=//p' "$t/index.theme" | tr ',' ' ')"
done
for th in $themes; do [ "$th" = hicolor ] && continue
  for t in "$HOME/.local/share/icons/$th" "/usr/share/icons/$th"; do
    [ -d "$t" ] && f=$(find -L "$t" -path "*apps*" \\( -name "$n.svg" -o -name "$n.png" \\) -print -quit 2>/dev/null) && [ -n "$f" ] && { echo "$f"; exit; }
  done
done
for d in "$HOME/.local/share/icons/hicolor" "$HOME/.local/share/flatpak/exports/share/icons/hicolor" /var/lib/flatpak/exports/share/icons/hicolor /usr/share/icons/hicolor; do
  for s in scalable 512x512 256x256 128x128 64x64 48x48; do for e in svg png; do [ -f "$d/$s/apps/$n.$e" ] && { echo "$d/$s/apps/$n.$e"; exit; }; done; done
done
for e in svg png; do [ -f "/usr/share/pixmaps/$n.$e" ] && { echo "/usr/share/pixmaps/$n.$e"; exit; }; done`, "icon-lookup", lookup.name]
            stdout: StdioCollector {
                onStreamFinished: {
                    const file = text.trim();
                    if (file !== "") root.iconFiles = Object.assign({}, root.iconFiles, { [lookup.name]: file });
                    lookup.destroy(); // Once its output is read: on exit it could still be on its way
                }
            }
        }
    }
    ColorQuantizer {
        id: iconColours
        source: root.iconFile !== "" ? "file://" + root.iconFile : ""
        depth: 2 // Four colours
        rescaleSize: 32
    }
    property color glowColour: { // Not readonly: it glides between apps (a Behavior needs a writable property)
        let best = Appearance.colors.colPrimary, bestScore = 0.12; // Below this it's grey or black: the accent
        for (const c of (iconColours.colors ?? [])) {
            const score = c.hsvSaturation * c.hsvValue;
            if (score > bestScore) { bestScore = score; best = c; }
        }
        return best;
    }
    Behavior on glowColour { ColorAnimation { duration: 250 } }

    // A symbol for a desktop action, from its name (apps often reuse their own logo for every action)
    function actionSymbol(name) {
        const n = (name ?? "").toLowerCase();
        if (n.includes("private") || n.includes("incognito")) return "visibility_off";
        if (n.includes("window")) return "open_in_new";
        if (n.includes("new")) return "add";
        if (n.includes("setting") || n.includes("preference")) return "settings";
        if (n.includes("quit") || n.includes("exit")) return "close";
        if (n.includes("play") || n.includes("pause")) return "play_pause";
        if (n.includes("store")) return "storefront";
        if (n.includes("library")) return "sports_esports";
        if (n.includes("community") || n.includes("friends")) return "groups";
        if (n.includes("screenshot")) return "photo_library";
        if (n.includes("profile")) return "manage_accounts";
        return "bolt";
    }
    // Tab from the list: into the first action. Tab, Shift+Tab or Left from an action: back to the list
    function focusActions() {
        actionRepeater.itemAt(0)?.forceActiveFocus();
    }
    function backToList() {
        root.item?.forceActiveFocus();
    }

    radius: 20
    // Tall enough for what it shows (an app with several actions is taller than the list's five rows): the
    // results row grows to this, so nothing is cut off or runs under the hints
    implicitHeight: body.implicitHeight + 24 * 2 + (hints.visible ? hints.height + 14 : 0)
    color: Appearance.colors.colLayer3 // The cards' surface, as the sidebar's
    clip: true

    // Cross-fade + small lift whenever the selection changes
    onItemChanged: swapAnim.restart()
    ParallelAnimation {
        id: swapAnim
        NumberAnimation { target: body; property: "opacity"; from: 0.25; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: body; property: "lift"; from: 8; to: 0; duration: 260; easing.type: Easing.OutCubic }
    }

    // A soft glow behind the hero icon, in the icon's own colour
    Shape {
        id: heroGlow
        anchors.horizontalCenter: parent.horizontalCenter
        y: body.y + heroBox.y + heroBox.height / 2 - height / 2
        width: 340
        height: 340
        visible: !root.isClipboardImage && !root.isClipboard
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: heroGlow.width / 2; centerY: heroGlow.height / 2
                focalX: centerX; focalY: centerY
                centerRadius: heroGlow.width // Stop 0.5 lands on the edge, as with the old effect
                GradientStop { position: 0.0; color: ColorUtils.transparentize(root.glowColour, 0.6) }
                GradientStop { position: 0.5; color: "transparent" }
            }
            PathRectangle { width: heroGlow.width; height: heroGlow.height }
        }
    }

    ColumnLayout {
        id: body
        property real lift: 0
        visible: root.hasItem
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            verticalCenterOffset: lift - (hints.visible ? (hints.height + 14) / 2 : 0) // Centred above the hints
            margins: 24
        }
        spacing: 10

        Item { // Hero: icon, emoji, symbol or clipboard image
            id: heroBox
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 6
            implicitWidth: heroLoader.implicitWidth
            implicitHeight: heroLoader.implicitHeight
            Loader {
                id: heroLoader
                anchors.centerIn: parent
                sourceComponent: root.isClipboardImage ? clipImage
                    : root.isEmoji ? emoji
                    : (root.hasItem && root.item.itemIcon !== "" && root.item.materialSymbol === "") ? appIcon
                    : symbol
            }
        }

        StyledText { // Title (math result shown large in monospace)
            Layout.fillWidth: true
            visible: !root.isClipboard
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: root.hasItem ? root.item.itemName : ""
            color: Appearance.colors.colOnLayer3
            font.pixelSize: root.isMath ? 30 : Appearance.font.pixelSize.huge
            font.family: root.isMath ? Appearance.font.family.monospace : Appearance.font.family.title
            font.weight: root.isMath ? Font.DemiBold : Font.Black
        }

        StyledText { // Description / kind
            Layout.fillWidth: true
            visible: !root.isClipboard && text !== ""
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            text: !root.hasItem ? ""
                : root.isApp ? root.item.itemSubtitle
                : root.item.itemType
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }

        StyledText { // Clipboard text, shown in full (up to a point)
            Layout.fillWidth: true
            Layout.maximumHeight: 190
            visible: root.isClipboard && !root.isClipboardImage
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 9
            elide: Text.ElideRight
            text: root.isClipboard ? root.item.itemName : ""
            color: Appearance.colors.colOnLayer1
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        RippleButton { // Primary action
            id: actionButton
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8
            implicitHeight: 40
            implicitWidth: actionRow.implicitWidth + 32
            buttonRadius: 12
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            onClicked: if (root.hasItem) root.item.clicked()
            contentItem: Item {
                RowLayout {
                    id: actionRow
                    anchors.centerIn: parent
                    spacing: 8
                    StyledText {
                        // Clipboard and emoji results have no action name; they copy
                        text: !root.hasItem ? ""
                            : root.item.itemClickActionName !== "" ? root.item.itemClickActionName
                            : (root.isClipboard || root.isEmoji) ? Translation.tr("Copy")
                            : Translation.tr("Open")
                        color: Appearance.colors.colOnPrimary
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                    }
                    StyledText {
                        text: "↵"
                        color: Appearance.colors.colOnPrimary
                        opacity: 0.7
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
        }

        ColumnLayout { // The result's own actions, named
            Layout.fillWidth: true
            Layout.topMargin: 12
            visible: root.actions.length > 0
            spacing: 4
            Repeater {
                id: actionRepeater
                model: root.actions
                delegate: RippleButton {
                    id: actionRow
                    required property var modelData
                    required property int index
                    // An app's actions often reuse its logo, which says nothing about what they do: a symbol then
                    readonly property bool reusesAppIcon: (modelData.icon ?? "") !== "" && modelData.icon === root.item?.itemIcon
                    readonly property string imageName: reusesAppIcon ? "" : (modelData.icon ?? "")
                    readonly property string symbolName: modelData.materialIcon ?? (imageName === "" ? root.actionSymbol(modelData.name) : "")
                    Layout.fillWidth: true
                    implicitHeight: 40
                    buttonRadiusTop: index === 0 ? Appearance.rounding.normal : Appearance.rounding.joined
                    buttonRadiusBottom: index === root.actions.length - 1 ? Appearance.rounding.normal : Appearance.rounding.joined
                    buttonRadius: Appearance.rounding.joined
                    colBackground: actionRow.activeFocus ? Appearance.colors.colLayer4Hover : Appearance.colors.colLayer4
                    colBackgroundHover: Appearance.colors.colLayer4Hover
                    colRipple: Appearance.colors.colLayer4Active
                    onClicked: {
                        GlobalStates.overviewOpen = false;
                        modelData.execute();
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Down) actionRepeater.itemAt(index + 1)?.forceActiveFocus();
                        else if (event.key === Qt.Key_Up) {
                            if (index > 0) actionRepeater.itemAt(index - 1).forceActiveFocus();
                            else root.backToList();
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) actionRow.clicked();
                        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab || event.key === Qt.Key_Left) root.backToList();
                        else return;
                        event.accepted = true;
                    }
                    contentItem: RowLayout {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        spacing: 10
                        MaterialSymbol {
                            visible: actionRow.symbolName !== ""
                            text: actionRow.symbolName
                            iconSize: 18
                            color: Appearance.colors.colOnLayer4
                        }
                        IconImage {
                            visible: actionRow.symbolName === ""
                            source: actionRow.imageName !== "" ? Quickshell.iconPath(actionRow.imageName) : ""
                            implicitSize: 18
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: actionRow.modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer4
                        }
                    }
                }
            }
        }
    }

    // Keyboard hints along the bottom
    RowLayout {
        id: hints
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
        visible: root.hasItem
        spacing: 6
        Hint { key: "↑↓"; label: Translation.tr("choose") }
        Hint { key: "↵"; label: root.isApp ? Translation.tr("launch") : Translation.tr("open") }
        Hint { visible: root.actions.length > 0; key: "Tab"; label: Translation.tr("actions") }
    }
    component Hint: RowLayout {
        property string key
        property string label
        spacing: 5
        Layout.leftMargin: 4
        Rectangle {
            implicitWidth: Math.max(22, keyText.implicitWidth + 12)
            implicitHeight: 22
            radius: 6
            color: Appearance.colors.colLayer4
            StyledText {
                id: keyText
                anchors.centerIn: parent
                text: parent.parent.key
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer4
            }
        }
        StyledText {
            text: parent.label
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }

    Component {
        id: appIcon
        IconImage {
            implicitSize: 88
            source: Quickshell.iconPath(root.item?.itemIcon || "image-missing") // No lookup for an empty name
        }
    }
    Component {
        id: emoji
        StyledText {
            text: root.item?.bigText ?? ""
            font.pixelSize: 72
        }
    }
    Component {
        id: symbol
        MaterialSymbol {
            text: root.item?.materialSymbol || "search"
            iconSize: 64
            color: Appearance.colors.colPrimary
        }
    }
    Component {
        id: clipImage
        CliphistImage {
            entry: root.item?.cliphistRawString ?? ""
            maxWidth: root.width - 48
            maxHeight: root.height - 120
        }
    }
}
