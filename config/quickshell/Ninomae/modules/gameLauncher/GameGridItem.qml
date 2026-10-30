import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Widgets
Item {
    id: root
    required property var game
    signal gameLaunched(var game)
    property bool hovered: mouseArea.containsMouse || favMouseArea.containsMouse || stateHoverHandler.hovered
    property bool _debouncedHover: false
    property bool showHoverEffect: _debouncedHover || activeFocus

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

    // Hover: the tile lifts with a soft dark shadow and a crisp lavender ring just outside it.
    // (Replaces a lavender drop-shadow haze that bled onto neighbouring tiles.)
    Item {
        id: hoverWrap
        // Room inside the slot so the lifted tile and its ring aren't clipped by the list
        anchors { fill: parent; topMargin: 12; bottomMargin: 4 }
        scale: root.showHoverEffect ? 1.02 : 1.0
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
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
            opacity: root.showHoverEffect ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        }
        Rectangle { // Focus ring, with a small gap from the tile
            anchors { fill: cardBackground; margins: -4 }
            radius: cardBackground.radius + 4
            color: "transparent"
            border.width: 2
            border.color: Appearance.colors.colPrimary
            opacity: root.showHoverEffect ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
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
        // Floating name pill: readable on any cover art, matches the shell's pill style
        Rectangle {
            id: hoverInfoBar
            readonly property real inset: 8
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: inset; rightMargin: inset }
            anchors.bottomMargin: root.showHoverEffect ? inset : -height
            height: 36
            radius: Appearance.rounding.container
            color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.1)
            z: 4
            opacity: root.showHoverEffect ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 4 }
                spacing: 6
                StyledText {
                    id: nameText
                    Layout.fillWidth: true
                    text: game.name || ""
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                Rectangle {
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: Appearance.rounding.segment
                    color: Appearance.colors.colPrimary
                    MaterialSymbol {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 1
                        text: "play_arrow"
                        iconSize: 18
                        fill: 1
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
        Rectangle { // Install state badge: an update waiting, a download running, or mods downloading
            id: stateBadge
            anchors { top: parent.top; left: parent.left; topMargin: 6; leftMargin: 6 }
            z: 10
            width: _stateRow.width + 14
            height: 24
            radius: Appearance.rounding.verysmall
            readonly property string _state: { const _ = GameLauncherService.games; return GameLauncherService.installState(game); }
            readonly property var _look: {
                switch (_state) {
                case "updateRequired": return { icon: "downloading", text: Translation.tr("Update"), tip: Translation.tr("Update available"), color: Appearance.colors.colPrimary };
                case "updatePaused":   return { icon: "downloading", text: Translation.tr("Update"), tip: Translation.tr("Update paused"), color: Appearance.colors.colPrimary };
                case "installing":     return { icon: "download", text: Translation.tr("Installing"), tip: Translation.tr("Game is installing"), color: Appearance.colors.colSecondary };
                case "updating":       return { icon: "download", text: Translation.tr("Updating"), tip: Translation.tr("Game is updating"), color: Appearance.colors.colSecondary };
                case "installed":
                    if (GameLauncherService.workshopDownloading[game?.id])
                        return { icon: "extension", text: Translation.tr("Mods"), tip: Translation.tr("Workshop mods are downloading"), color: Appearance.colors.colSecondary };
                    if (GameLauncherService.updatedSincePlayed(game)) // Patched since you last played: News has the notes
                        return { icon: "new_releases", text: Translation.tr("Updated"), tip: Translation.tr("Updated since you last played · goes once you play it or read its News"), color: Appearance.colors.colTertiary };
                }
                return null;
            }
            visible: _look !== null
            color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.15)
            property bool hovered: stateHoverHandler.hovered
            HoverHandler { id: stateHoverHandler }
            Row {
                id: _stateRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: stateBadge._look?.icon ?? ""
                    iconSize: 13; fill: 1
                    color: stateBadge._look?.color ?? Appearance.colors.colSecondary
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
        Item {
            id: favButton
            anchors { top: parent.top; right: parent.right; topMargin: 6; rightMargin: 6 }
            z: 10; width: 24; height: 24
            property bool hovered: favMouseArea.containsMouse
            property bool isFav: {
                const _ = GameLauncherService.favoritesSet;
                return game ? _.has(game.id) : false;
            }
            opacity: (isFav || root.showHoverEffect) ? 1.0 : 0.0; visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Rectangle {
                id: favGlow
                anchors.centerIn: parent
                width: favButton.isFav ? 28 : 0; height: width; radius: width / 2
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
                opacity: favButton.isFav ? 1.0 : 0.0
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
            Rectangle {
                id: favBg
                anchors.fill: parent; radius: Appearance.rounding.verysmall
                color: favButton.isFav
                    ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.2)
                    : (favMouseArea.containsMouse
                        ? ColorUtils.transparentize(Appearance.colors.colLayer0, 0.2)
                        : ColorUtils.transparentize(Appearance.colors.colLayer0, 0.4))
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            MaterialSymbol {
                id: starIcon
                anchors.centerIn: parent
                text: "star"
                fill: favButton.isFav ? 1 : 0
                iconSize: 14
                color: favButton.isFav ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                Behavior on fill { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 200 } }
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
}
