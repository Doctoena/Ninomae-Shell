import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The crosshair overlay (services/Crosshair.qml in the shell). On the left, fixed: a big live preview (on dark,
 * light or the wallpaper, at 1×, 3× or 6×), five styles to start from (a click sets the parts, keeping the
 * colour), the colour as swatches (the accent, six usual crosshair colours, Custom for the full picker) and
 * Show on screen. On the right, scrolling: the full picker while Custom is open, then the parts (outline,
 * inner lines, outer lines, centre dot, circle) as joined rows, each with its switch and what it's set to; the
 * open one shows its settings, two to a row. Which games it shows in is set per game, with the crosshair button
 * under Play on a game's page in the launcher.
 */
Item {
    id: page
    readonly property var opts: Config.options.crosshair

    // A number setting: `key` in the crosshair config, in pixels as drawn in games. Two to a row in a part
    component Num: ConfigSpinBox {
        required property string key
        option: "crosshair." + key
        suffix: "px"
        stepSize: 1
        verticalPadding: 10
        Layout.fillWidth: true
        Layout.preferredWidth: 1 // Even columns
    }
    component OpacityNum: Num {
        text: Translation.tr("Opacity")
        suffix: "%"
        from: 10; to: 100; stepSize: 10
    }

    // ── The colour: the accent, the usual crosshair colours, or any (Custom) ──
    readonly property var swatches: ["#59f5bb", "#3fe0ff", "#ff4b5c", "#ffe14b", "#ffffff", "#ff5cf0"]
    readonly property bool customColour: opts.color !== "accent" && !swatches.includes(String(opts.color).toLowerCase())
    property bool pickerOpen: customColour
    readonly property color shownColour: opts.color === "accent" ? Appearance.colors.colPrimary : opts.color

    // ── Styles: starting points. A click sets the parts (not the colour); one matching what's set is lit ──
    readonly property var styles: [
        { name: Translation.tr("Classic"), set: { lines: true, topLine: true, length: 6, verticalLength: 0, thickness: 2, gap: 3, outerLines: false, dot: false, circle: false } },
        { name: Translation.tr("Dot"), set: { lines: false, outerLines: false, dot: true, dotSize: 3, circle: false } },
        { name: "T", set: { lines: true, topLine: false, length: 6, verticalLength: 0, thickness: 2, gap: 3, outerLines: false, dot: false, circle: false } },
        { name: Translation.tr("Circle"), set: { lines: false, outerLines: false, dot: true, dotSize: 2, circle: true, circleRadius: 8, circleThickness: 1 } },
        { name: Translation.tr("Tight"), set: { lines: true, topLine: true, length: 4, verticalLength: 0, thickness: 2, gap: 1, outerLines: false, dot: true, dotSize: 2, circle: false } }
    ]
    function applyStyle(set) { for (const k in set) Config.options.crosshair[k] = set[k]; }
    function styleMatches(set) { return Object.keys(set).every(k => page.opts[k] === set[k]); }
    function withStyle(set) { // What the crosshair would be with a style: for its tile's own preview
        const o = {};
        for (const k of Object.keys(page.opts)) o[k] = page.opts[k];
        return Object.assign(o, set);
    }

    // The part whose settings are open
    property string openPart: "lines"
    // Settings search: a result in one of the parts opens it (true: it was a part)
    function openSection(title) {
        const part = { [Translation.tr("Outline")]: "outline", [Translation.tr("Inner lines")]: "lines",
                       [Translation.tr("Outer lines")]: "outerLines", [Translation.tr("Centre dot")]: "dot",
                       [Translation.tr("Circle")]: "circle" }[title];
        if (!part) return false;
        page.openPart = part;
        return true;
    }
    // The preview's backdrop and zoom
    property string backdrop: "dark"
    property int zoom: 3

    // Each part's line: what it's set to, or Off
    function partLine(part) {
        const o = page.opts;
        const on = part === "outline" ? o.outline : part === "lines" ? o.lines : part === "outerLines" ? o.outerLines : part === "dot" ? o.dot : o.circle;
        if (!on) return Translation.tr("Off");
        return part === "outline" ? `${o.outlineThickness} px  ·  ${o.outlineOpacity}%`
            : part === "lines" ? Translation.tr("%1 px  ·  gap %2").arg(o.length).arg(o.gap) + (o.topLine ? "" : "  ·  T")
            : part === "outerLines" ? Translation.tr("%1 px  ·  gap %2").arg(o.outerLength).arg(o.outerGap)
            : part === "dot" ? `${o.dotSize} px`
            : `${o.circleRadius} px`;
    }

    // The same width as the other pages' cards (ContentPage's maxWidth), centred under the header
    RowLayout {
        id: columns
        anchors { top: parent.top; bottom: parent.bottom; topMargin: 20 }
        width: Math.min(parent.width - 40, 1260)
        x: (parent.width - width) / 2
        spacing: 24

        // ── Left: the preview, styles, colour, show on screen ──
        ColumnLayout {
            Layout.fillWidth: false // A layout fills by default: the parts get the room
            // 440, down to 300 in a narrow (tiled) window, so the parts keep 440 for their labels
            Layout.preferredWidth: Math.max(300, Math.min(440, columns.width - columns.spacing - 440))
            Layout.fillHeight: true
            spacing: 8

            Rectangle { // The preview, drawn as in games and scaled up
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(width * 0.8, 360)
                radius: Appearance.rounding.normal
                color: page.backdrop === "light" ? "#d9d6de" : "#0e0d12"
                border.width: page.backdrop === "dark" ? 1 : 0 // An edge: the dark one is near the page's colour
                border.color: Appearance.colors.colLayer4
                clip: true
                Image {
                    anchors.fill: parent
                    visible: page.backdrop === "wallpaper"
                    source: page.backdrop === "wallpaper" && Config.wallpaperPath ? "file://" + Config.wallpaperPath : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 900
                    asynchronous: true
                }
                CrosshairShape {
                    anchors.centerIn: parent
                    width: implicitWidth; height: implicitHeight
                    scale: page.zoom
                    smooth: false // Whole pixels, scaled up: sharp, as in games
                }
                ChipRow { // Its backdrop
                    anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
                    value: page.backdrop
                    options: [{ value: "dark", label: Translation.tr("Dark") }, { value: "light", label: Translation.tr("Light") },
                              { value: "wallpaper", label: Translation.tr("Wallpaper") }]
                    onPicked: v => page.backdrop = v
                }
                ChipRow { // How big
                    anchors { right: parent.right; bottom: parent.bottom; margins: 10 }
                    value: String(page.zoom)
                    options: [{ value: "1", label: "1×" }, { value: "3", label: "3×" }, { value: "6", label: "6×" }]
                    onPicked: v => page.zoom = parseInt(v)
                }
            }

            RowLayout { // Styles: a tile each, its own preview and name
                Layout.fillWidth: true
                spacing: 3
                Repeater {
                    model: page.styles
                    RippleButton {
                        id: styleTile
                        required property var modelData
                        required property int index
                        readonly property bool active: page.styleMatches(modelData.set)
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 84
                        padding: 0
                        buttonRadiusTopLeft: index === 0 ? Appearance.rounding.small : Appearance.rounding.joined
                        buttonRadiusBottomLeft: buttonRadiusTopLeft
                        buttonRadiusTopRight: index === page.styles.length - 1 ? Appearance.rounding.small : Appearance.rounding.joined
                        buttonRadiusBottomRight: buttonRadiusTopRight
                        colBackground: active ? Appearance.colors.colLayer3Accent : Appearance.colors.colLayer3
                        colBackgroundHover: active ? Appearance.colors.colLayer3AccentHover : Appearance.colors.colLayer3Hover
                        colRipple: Appearance.colors.colLayer3Active
                        onClicked: page.applyStyle(modelData.set)
                        contentItem: Item {
                            Item { // Its look at 2×, in the space over the name
                                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: styleName.top }
                                clip: true
                                CrosshairShape {
                                    anchors.centerIn: parent
                                    width: implicitWidth; height: implicitHeight
                                    opts: page.withStyle(styleTile.modelData.set)
                                    scale: 2
                                    smooth: false
                                }
                            }
                            StyledText {
                                id: styleName
                                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
                                text: styleTile.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: styleTile.active ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }

            Rectangle { // Colour: swatches, then Custom
                Layout.fillWidth: true
                implicitHeight: 54
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer3
                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 5
                    Swatch { // The accent: follows the wallpaper
                        fill: Appearance.colors.colPrimary
                        picked: page.opts.color === "accent"
                        glyph: "wallpaper"
                        tip: Translation.tr("Accent colour · follows the wallpaper")
                        onClicked: { page.opts.color = "accent"; page.pickerOpen = false; }
                    }
                    Repeater {
                        model: page.swatches
                        Swatch {
                            required property string modelData
                            fill: modelData
                            picked: String(page.opts.color).toLowerCase() === modelData
                            onClicked: { page.opts.color = modelData; page.pickerOpen = false; }
                        }
                    }
                    RippleButton { // Any colour: the picker, over the parts
                        Layout.fillWidth: true
                        Layout.minimumWidth: 34
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.verysmall + 2
                        colBackground: page.pickerOpen || page.customColour ? Appearance.colors.colLayer3Accent : Appearance.colors.colLayer4
                        colBackgroundHover: Appearance.colors.colLayer4Hover
                        onClicked: page.pickerOpen = !page.pickerOpen
                        contentItem: Row {
                            anchors.centerIn: parent
                            spacing: 5
                            Rectangle { // The custom colour, when it's one
                                anchors.verticalCenter: parent.verticalCenter
                                visible: page.customColour
                                width: 14; height: 14; radius: 4
                                color: page.shownColour
                            }
                            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; visible: !page.customColour; text: "palette"; iconSize: 16; color: Appearance.colors.colOnLayer3 }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Translation.tr("Custom")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: page.pickerOpen || page.customColour ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                            }
                        }
                    }
                }
            }

            RowLayout { // Show it on screen; when it shows in games
                Layout.fillWidth: true
                spacing: 3
                RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 42
                    buttonRadiusTopLeft: Appearance.rounding.small; buttonRadiusBottomLeft: Appearance.rounding.small
                    buttonRadiusTopRight: Appearance.rounding.joined; buttonRadiusBottomRight: Appearance.rounding.joined
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    colRipple: Appearance.colors.colLayer3Active
                    downAction: () => Quickshell.execDetached(["qs", "-c", "Ninomae", "ipc", "call", "crosshair", "test"])
                    contentItem: Row {
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "visibility"; iconSize: 18; color: Appearance.colors.colOnLayer3 }
                        StyledText { anchors.verticalCenter: parent.verticalCenter; text: Translation.tr("Show on screen"); color: Appearance.colors.colOnLayer3 }
                    }
                }
                Rectangle { // When it shows in games, said on hover
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 42
                    color: Appearance.colors.colLayer3
                    topLeftRadius: Appearance.rounding.joined; bottomLeftRadius: Appearance.rounding.joined
                    topRightRadius: Appearance.rounding.small; bottomRightRadius: Appearance.rounding.small
                    HoverHandler { id: gamesHover }
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "keyboard"; iconSize: 18; color: Appearance.colors.colSubtext }
                        StyledText { anchors.verticalCenter: parent.verticalCenter; text: Translation.tr("Super+G in games"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                    }
                    StyledToolTip {
                        extraVisibleCondition: gamesHover.hovered
                        text: Translation.tr("Shows in the games you turn it on for, with the crosshair button under Play on a game's page. Super+G shows or hides it.")
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }

        // ── Right, scrolling: the picker while Custom is open, then the parts ──
        ContentPage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            margin: 0
            ContentSection {
                visible: page.pickerOpen
                title: Translation.tr("Custom colour")
                ColorPicker {
                    Layout.fillWidth: true
                    color: page.shownColour
                    onEdited: c => page.opts.color = c.toString()
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3 // Joined
                StyledText {
                    Layout.bottomMargin: 5
                    text: Translation.tr("Parts")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }
                PartRow {
                    part: "outline"; iconName: "border_outer"; title: Translation.tr("Outline"); first: true
                    Num { key: "outlineThickness"; text: Translation.tr("Thickness"); from: 1; to: 4 }
                    OpacityNum { key: "outlineOpacity" }
                }
                PartRow {
                    part: "lines"; iconName: "add"; title: Translation.tr("Inner lines")
                    Num { key: "length"; text: Translation.tr("Length"); from: 1; to: 30 }
                    Num { key: "verticalLength"; text: Translation.tr("Vertical length"); tooltip: Translation.tr("0 uses the same length"); from: 0; to: 30 }
                    Num { key: "thickness"; text: Translation.tr("Thickness"); from: 1; to: 10 }
                    Num { key: "gap"; text: Translation.tr("Gap from the centre"); from: 0; to: 30 }
                    OpacityNum { key: "lineOpacity" }
                    ConfigSwitch {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: Translation.tr("Top line")
                        tooltip: Translation.tr("Off makes a T shape, for the outer lines too")
                        option: "crosshair.topLine"
                    }
                }
                PartRow {
                    part: "outerLines"; iconName: "open_with"; title: Translation.tr("Outer lines")
                    Num { key: "outerLength"; text: Translation.tr("Length"); from: 1; to: 30 }
                    Num { key: "outerThickness"; text: Translation.tr("Thickness"); from: 1; to: 10 }
                    Num { key: "outerGap"; text: Translation.tr("Gap from the centre"); from: 0; to: 40 }
                    OpacityNum { key: "outerOpacity" }
                    ConfigSwitch { // Also here when the inner lines are off: it shapes these too
                        visible: !page.opts.lines
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: Translation.tr("Top line")
                        tooltip: Translation.tr("Off makes a T shape")
                        option: "crosshair.topLine"
                    }
                }
                PartRow {
                    part: "dot"; iconName: "fiber_manual_record"; title: Translation.tr("Centre dot")
                    Num { key: "dotSize"; text: Translation.tr("Size"); from: 1; to: 10 }
                    OpacityNum { key: "dotOpacity" }
                }
                PartRow {
                    part: "circle"; iconName: "radio_button_unchecked"; title: Translation.tr("Circle"); last: true
                    Num { key: "circleRadius"; text: Translation.tr("Size"); from: 3; to: 40 }
                    Num { key: "circleThickness"; text: Translation.tr("Thickness"); from: 1; to: 6 }
                    OpacityNum { key: "circleOpacity" }
                }
            }
        }
    }

    // A part as a joined row: its icon (the accent while it's on), name, what it's set to, and its switch. A click
    // on the row opens its settings under it (its children, two to a row), closing the one that was open
    component PartRow: Rectangle {
        id: partRow
        required property string part
        property string iconName
        property string title
        property bool first: false
        property bool last: false
        default property alias settings: grid.data
        readonly property bool isOn: page.opts[part] ?? false
        readonly property bool open: page.openPart === part
        Layout.fillWidth: true
        implicitHeight: 52 + (open ? grid.implicitHeight + 6 : 0)
        Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        clip: true
        color: Appearance.colors.colLayer3
        topLeftRadius: first ? Appearance.rounding.normal : Appearance.rounding.joined
        topRightRadius: topLeftRadius
        bottomLeftRadius: last ? Appearance.rounding.normal : Appearance.rounding.joined
        bottomRightRadius: bottomLeftRadius
        RippleButton { // The row's head: opens it
            id: head
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 52
            padding: 0
            buttonRadiusTopLeft: partRow.topLeftRadius; buttonRadiusTopRight: partRow.topRightRadius
            buttonRadiusBottomLeft: partRow.open || !partRow.last ? Appearance.rounding.joined : partRow.bottomLeftRadius
            buttonRadiusBottomRight: buttonRadiusBottomLeft
            colBackground: partRow.open ? Appearance.colors.colLayer3Accent : Appearance.colors.colLayer3
            colBackgroundHover: partRow.open ? Appearance.colors.colLayer3AccentHover : Appearance.colors.colLayer3Hover
            colRipple: Appearance.colors.colLayer3Active
            onClicked: page.openPart = partRow.open ? "" : partRow.part
            contentItem: RowLayout {
                anchors { fill: parent; leftMargin: 8; rightMargin: 12 }
                spacing: 12
                Rectangle {
                    implicitWidth: 36; implicitHeight: 36
                    radius: Appearance.rounding.small
                    color: partRow.isOn ? Appearance.colors.colPrimary : Appearance.colors.colLayer4
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: partRow.iconName
                        iconSize: 18
                        fill: partRow.isOn ? 1 : 0
                        color: partRow.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                    }
                }
                StyledText {
                    Layout.preferredWidth: 130
                    text: partRow.title
                    font.weight: Font.DemiBold
                    color: partRow.open ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: page.partLine(partRow.part)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                MaterialSymbol {
                    text: partRow.open ? "expand_less" : "expand_more"
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                }
                StyledSwitch {
                    checked: partRow.isOn
                    onClicked: Config.options.crosshair[partRow.part] = !partRow.isOn
                }
            }
        }
        GridLayout {
            id: grid
            anchors { left: parent.left; right: parent.right; top: head.bottom; margins: 3; topMargin: 3 }
            visible: partRow.open
            columns: 2
            columnSpacing: 3
            rowSpacing: 3
        }
    }

    // Choices as joined chips over the preview: the picked one tinted
    component ChipRow: Row {
        id: chipRow
        property var options: []
        property string value
        signal picked(string v)
        spacing: 3
        Repeater {
            model: chipRow.options
            RippleButton {
                id: chip
                required property var modelData
                required property int index
                readonly property bool active: chipRow.value === modelData.value
                implicitHeight: 28
                implicitWidth: chipLabel.implicitWidth + 22
                padding: 0
                buttonRadiusTopLeft: index === 0 ? Appearance.rounding.verysmall : Appearance.rounding.joined
                buttonRadiusBottomLeft: buttonRadiusTopLeft
                buttonRadiusTopRight: index === chipRow.options.length - 1 ? Appearance.rounding.verysmall : Appearance.rounding.joined
                buttonRadiusBottomRight: buttonRadiusTopRight
                colBackground: active ? Appearance.colors.colLayer3Accent : ColorUtils.transparentize(Appearance.colors.colLayer3, 0.1)
                colBackgroundHover: active ? Appearance.colors.colLayer3AccentHover : Appearance.colors.colLayer3Hover
                onClicked: chipRow.picked(chip.modelData.value)
                contentItem: StyledText {
                    id: chipLabel
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: chip.modelData.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: chip.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                }
            }
        }
    }

    // A colour to pick: ringed while it's the one in use
    component Swatch: RippleButton {
        id: swatch
        property color fill
        property bool picked: false
        property string glyph: ""
        property string tip: ""
        implicitWidth: 34; implicitHeight: 34
        padding: 0
        buttonRadius: Appearance.rounding.verysmall + 2
        colBackground: fill
        colBackgroundHover: fill
        colRipple: ColorUtils.transparentize("black", 0.7)
        contentItem: Item {
            Rectangle { // The ring, in the page's text colour
                anchors.fill: parent
                radius: swatch.buttonRadius
                color: "transparent"
                border.width: swatch.picked ? 3 : 0
                border.color: Appearance.colors.colOnLayer0
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: swatch.glyph !== ""
                text: swatch.glyph
                iconSize: 16
                color: Appearance.colors.colOnPrimary
            }
        }
        StyledToolTip { text: swatch.tip; extraVisibleCondition: swatch.tip !== "" }
    }
}
