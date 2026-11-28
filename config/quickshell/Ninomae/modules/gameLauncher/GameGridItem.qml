import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Widgets
Item {
    id: root
    required property var game
    signal gameLaunched(var game)
    property bool hovered: mouseArea.containsMouse || favMouseArea.containsMouse || stateHoverHandler.hovered || hoverInfoBar.buttonHovered
    property bool _debouncedHover: false
    property bool showHoverEffect: _debouncedHover || activeFocus

    // The ▶ on hover: for an installed game that isn't running (GameLauncherService.quickLaunch)
    readonly property bool _canPlay: stateBadge._state === "installed" && !stateBadge._playing
    // The favourite's bookmark: shoulders curving into the tile's top edge, a notch at the bottom (favButton's sizes)
    component RibbonShape: Shape {
        property color fill
        width: favButton.width; height: favButton.height
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 0
            fillColor: fill
            startX: 0; startY: 0
            PathArc { x: favButton.shoulder; y: favButton.shoulder; radiusX: favButton.shoulder; radiusY: favButton.shoulder; direction: PathArc.Clockwise }
            PathLine { x: favButton.shoulder; y: favButton.ribbonH }
            PathLine { x: favButton.shoulder + favButton.ribbonW / 2; y: favButton.ribbonH - favButton.notch }
            PathLine { x: favButton.shoulder + favButton.ribbonW; y: favButton.ribbonH }
            PathLine { x: favButton.shoulder + favButton.ribbonW; y: favButton.shoulder }
            PathArc { x: favButton.ribbonW + 2 * favButton.shoulder; y: 0; radiusX: favButton.shoulder; radiusY: favButton.shoulder; direction: PathArc.Clockwise }
            PathLine { x: 0; y: 0 }
        }
    }
    // Debounce hover to prevent rapid-fire animation starts when sweeping across tiles
    Timer {
        id: _hoverDebounce
        interval: 35
        onTriggered: root._debouncedHover = true
    }

    onHoveredChanged: {
        if (hovered) {
            _hoverDebounce.restart()
        } else {
            _hoverDebounce.stop()
            root._debouncedHover = false
        }
    }

    // Hover: the tile lifts with a soft dark shadow and a crisp lavender ring just outside it. Not scaled: that
    // resampled the art, a little soft while hovered.
    // (Replaces a lavender drop-shadow haze that bled onto neighbouring tiles.)
    Item {
        id: hoverWrap
        // Room inside the slot so the lifted tile and its ring aren't clipped by the list
        anchors { fill: parent; topMargin: 12; bottomMargin: 4 }
        transform: Translate {
            y: root.showHoverEffect ? -4 : 0
            Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        }
        RectangularShadow {
            anchors.fill: cardBackground
            radius: cardBackground.radius
            offset.y: 10
            blur: 22
            spread: -4
            color: Qt.rgba(0, 0, 0, 0.5)
            // Glass: a soft shadow at rest too (as the game page's pieces), deeper as the tile lifts
            opacity: root.showHoverEffect ? 1 : 0.4
            Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        }
        Rectangle { // Focus ring, with a small gap from the tile (the favourite's ribbon follows its fade)
            id: focusRing
            anchors { fill: cardBackground; margins: -4 }
            radius: cardBackground.radius + 4
            color: "transparent"
            border.width: 2
            border.color: Appearance.colors.colPrimary
            opacity: root.showHoverEffect ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } } // With the lift
        }
    Rectangle {
        id: cardBackground
        anchors.fill: parent
        color: "transparent"; radius: Appearance.rounding.small; clip: true
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            z: 1
            acceptedButtons: Qt.LeftButton
            onClicked: root.gameLaunched(game)
            cursorShape: Qt.PointingHandCursor
        }
        ClippingRectangle { // Rounded box art without an offscreen layer per tile (a whole library of those)
            anchors.fill: parent
            radius: cardBackground.radius
            color: "transparent"
            Image {
                id: boxArtImage
                anchors.fill: parent
                // Cached: a tile that comes back while typing or scrolling shows its art at once instead of
                // reloading it from disk and fading in. Safe now that every custom cover gets a new file name
                source: {
                    const customArt = GameLauncherService.customArt[game?.id];
                    const _ = GameLauncherService.customArtRevision;
                    if (customArt?.boxArt?.startsWith("/")) return customArt.boxArt;
                    if (game?.boxArt?.startsWith("/")) return game.boxArt;
                    if (GameLauncherService.fallbackToIcons && game?.icon?.startsWith("/")) return game.icon;
                    return "";
                }
                fillMode: Image.PreserveAspectCrop
                // Decode at tile size instead of the art's full resolution (often 600x900+). Based on the
                // width only: the height follows the launcher panel while it animates (details/stats ↔ grid),
                // and a changing sourceSize reloads every tile each frame, which made them flicker
                sourceSize: Qt.size(Math.round(width * Screen.devicePixelRatio), Math.round(width * 2 * Screen.devicePixelRatio))
                asynchronous: true
                opacity: status === Image.Ready ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
                Rectangle {
                    anchors.fill: parent
                    color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.12)
                    visible: parent.status !== Image.Ready; radius: cardBackground.radius
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "videogame_asset"
                            iconSize: 44
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: game.name || ""
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            Layout.maximumWidth: root.width - 20
                        }
                    }
                }
            }
        }
        Rectangle { // Glass: the fine edge light round the cover, as round the game page's glass
            visible: boxArtImage.status === Image.Ready
            anchors.fill: parent
            radius: cardBackground.radius
            color: "transparent"
            border { width: 1; color: ColorUtils.transparentize("white", 0.84) }
        }
        // Light bottom shade on hover, just for depth (the name pill below carries the text)
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height * 0.4
            radius: cardBackground.radius // clip is rectangular, so match the tile's rounded corners
            opacity: root.showHoverEffect ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: ColorUtils.transparentize("#000000", 0.55) }
            }
        }
        // On hover, the glass piece: the name over its hours and when it was last played, and ▶, which starts it
        TileGlassPiece {
            id: hoverInfoBar
            readonly property real inset: 6
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: inset; rightMargin: inset }
            anchors.bottomMargin: root.showHoverEffect ? inset : -height
            z: 4
            opacity: root.showHoverEffect ? 1.0 : 0.0
            visible: opacity > 0 // Not drawn on a library of tiles at rest
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            name: game?.name ?? ""
            minutes: game?.playtime ?? 0
            lastPlayed: root.showHoverEffect ? (game?.lastPlayed ?? 0) : 0
            showButton: root._canPlay
            onButtonClicked: GameLauncherService.quickLaunch(root.game, () => root.gameLaunched(root.game)) // Asks on its page
        }
        Rectangle { // State badge: playing now, an update waiting, a download running, or mods downloading
            id: stateBadge
            anchors { top: parent.top; left: parent.left; topMargin: 6; leftMargin: 6 }
            z: 10
            width: _stateRow.width + 16
            height: 26
            radius: 9
            border { width: 1; color: ColorUtils.transparentize("white", 0.9) } // A glass piece, as the hover piece
            readonly property string _state: { const _ = GameLauncherService.games; return GameLauncherService.installState(game); }
            // Running now (GameClips' watcher: however it was started, once its window is up): over the rest
            readonly property bool _playing: !!game && GameClips.gameId === game.id
            readonly property var _look: {
                if (_playing)
                    return { icon: "", text: Translation.tr("Playing"), tip: Translation.tr("Running now · Super+Shift+G for the overlay"), color: Appearance.colors.colPrimary };
                switch (_state) {
                case "updateRequired": return { icon: "downloading", text: Translation.tr("Update"), tip: Translation.tr("Update available"), color: Appearance.colors.colPrimary };
                case "updatePaused":   return { icon: "downloading", text: Translation.tr("Update"), tip: Translation.tr("Update paused"), color: Appearance.colors.colPrimary };
                case "installing":     return { icon: "download", text: Translation.tr("Installing"), tip: Translation.tr("Game is installing"), color: Appearance.colors.colSecondary };
                case "installPaused":  return { icon: "pause_circle", text: Translation.tr("Paused"), tip: Translation.tr("Install paused"), color: Appearance.colors.colSecondary };
                case "installQueued":  return { icon: "schedule", text: Translation.tr("Queued"), tip: Translation.tr("Waiting in Steam's download queue"), color: Appearance.colors.colSecondary };
                case "updateQueued":   return { icon: "schedule", text: Translation.tr("Update"), tip: Translation.tr("Update queued"), color: Appearance.colors.colPrimary };
                case "updating":       return { icon: "download", text: Translation.tr("Updating"), tip: Translation.tr("Game is updating"), color: Appearance.colors.colSecondary };
                case "installed":
                    if (GameLauncherService.workshopDownloading[game?.id])
                        return { icon: "extension", text: Translation.tr("Mods"), tip: Translation.tr("Workshop mods are downloading"), color: Appearance.colors.colSecondary };
                    if (GameLauncherService.updatedSincePlayed(game)) // Patched since you last played: News has the notes
                        return { icon: "new_releases", text: Translation.tr("Updated"), tip: Translation.tr("Updated since you last played"), color: Appearance.colors.colTertiary };
                }
                return null;
            }
            visible: _look !== null
            color: hoverInfoBar.glass
            property bool hovered: stateHoverHandler.hovered // Its tooltip shows on this
            HoverHandler { id: stateHoverHandler }
            Row {
                id: _stateRow
                anchors.centerIn: parent
                spacing: 5
                PlayingDot { // Playing: where the icon goes
                    anchors.verticalCenter: parent.verticalCenter
                    visible: stateBadge._playing && stateBadge.visible
                }
                Rectangle { // Its icon on a small squircle tinted in its colour
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !stateBadge._playing
                    width: 16; height: 16; radius: 5
                    color: ColorUtils.transparentize(stateBadge._look?.color ?? Appearance.colors.colSecondary, 0.78)
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: stateBadge._look?.icon ?? ""
                        iconSize: 12; fill: 1
                        color: stateBadge._look?.color ?? Appearance.colors.colSecondary
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: stateBadge._look?.text ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }
            }
            StyledToolTip {
                text: stateBadge._look?.tip ?? ""
            }
        }
    }
        Item { // Favourite: a bookmark hanging from the tile's top edge, its shoulders curving into it. At rest a
            // short tab in the grid's own colour, just the star, clear of the logo most covers put across the top;
            // on hover it drops to full length in the accent, reaching up into the ring.
            // Not a favourite: the same plain bookmark on hover, an outline star to click
            id: favButton
            anchors { top: cardBackground.top; topMargin: -reach; right: cardBackground.right; rightMargin: 12 }
            z: 10
            readonly property real shoulder: 6
            readonly property real ribbonW: 24
            readonly property real reach: isFav ? 4 * focusRing.opacity : 0 // A favourite's: up into the ring as it comes in
            readonly property real drop: focusRing.opacity // 0 at rest (a 22 px tab), 1 on hover (36 px)
            readonly property real ribbonH: 22 + 14 * drop + reach
            readonly property real notch: 4 + 3 * drop
            readonly property real starTop: 2 + 4 * drop + reach
            width: ribbonW + 2 * shoulder; height: ribbonH
            readonly property bool hovered: favMouseArea.containsMouse
            // How full the accent was when the pointer left (it fades from there with the ring)
            property real leaveFrom: 1
            readonly property bool isFav: {
                const _ = GameLauncherService.favoritesSet;
                return game ? _.has(game.id) : false;
            }
            opacity: (isFav || root.showHoverEffect) ? 1.0 : 0.0; visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            RibbonShape { fill: Appearance.colors.colLayer1 } // The grid's colour: a favourite at rest, or one to click on hover
            Connections {
                target: root
                function onShowHoverEffectChanged() { if (!root.showHoverEffect) favButton.leaveFrom = Math.max(0.01, focusRing.opacity); }
            }
            Item { // On hover the accent fills it from the ring down, step for step with the ring coming in; when the
                // pointer leaves it fades with the ring, from as full as it got
                width: parent.width
                height: parent.height * (root.showHoverEffect ? focusRing.opacity : favButton.leaveFrom)
                opacity: root.showHoverEffect ? 1 : focusRing.opacity / favButton.leaveFrom
                visible: favButton.isFav && height > 0 && opacity > 0
                clip: true
                z: 1
                RibbonShape { fill: Appearance.colors.colPrimary }
                MaterialSymbol { // The star over the accent
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: favButton.starTop }
                    text: "star"; fill: 1; iconSize: starIcon.iconSize
                    color: Appearance.colors.colOnPrimary
                    transform: Scale { // Pops with the star under it
                        origin.x: starIcon.width / 2; origin.y: starIcon.height / 2
                        xScale: starScale.xScale; yScale: starScale.yScale
                    }
                }
            }
            MaterialSymbol {
                id: starIcon
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: favButton.starTop }
                text: "star"
                fill: favButton.isFav ? 1 : 0
                iconSize: Math.round(13 + 2 * favButton.drop)
                color: favButton.isFav || favButton.hovered ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on fill { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                transform: Scale {
                    id: starScale
                    origin.x: starIcon.width / 2
                    origin.y: starIcon.height / 2
                    xScale: 1; yScale: 1
                }
                SequentialAnimation {
                    id: popAnim
                    NumberAnimation { target: starScale; properties: "xScale,yScale"; to: 1.4; duration: 120; easing.type: Easing.OutBack }
                    NumberAnimation { target: starScale; properties: "xScale,yScale"; to: 1.0; duration: 200; easing.type: Easing.OutElastic }
                }
            }
            MouseArea {
                id: favMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (game) {
                        GameLauncherService.toggleFavorite(game.id);
                        popAnim.restart();
                    }
                }
            }
            StyledToolTip {
                text: favButton.isFav ? Translation.tr("Remove from favorites") : Translation.tr("Add to favorites")
            }
        }
    }
}
