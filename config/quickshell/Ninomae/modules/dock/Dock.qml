import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
Scope { // Scope
    id: root
    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false
    Variants {
        // For each monitor
        model: Quickshell.screens
        PanelWindow {
            id: dockRoot
            // Window
            required property var modelData
            screen: modelData
            visible: !GlobalStates.screenLocked
            property bool reveal: root.pinned || (Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse) || dockApps.requestDockShow || (!ToplevelManager.activeToplevel?.activated)
            anchors {
                bottom: true
                left: true
                right: true
            }
            exclusiveZone: root.pinned ? implicitHeight - (Appearance.sizes.hyprlandGapsOut) - (Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut) : 0
            implicitWidth: dockBackground.implicitWidth
            WlrLayershell.namespace: "quickshell:dock"
            color: "transparent"
            implicitHeight: (Config.options?.dock.height ?? 70) + Appearance.sizes.elevationMargin + Appearance.sizes.hyprlandGapsOut
            mask: Region {
                item: dockMouseArea
            }
            MouseArea {
                id: dockMouseArea
                height: parent.height
                anchors {
                    top: parent.top
                    topMargin: dockRoot.reveal ? 0 : Config.options?.dock.hoverToReveal ? (dockRoot.implicitHeight - Config.options.dock.hoverRegionHeight) : (dockRoot.implicitHeight + 1)
                    horizontalCenter: parent.horizontalCenter
                }
                implicitWidth: dockHoverRegion.implicitWidth + Appearance.sizes.elevationMargin * 2
                hoverEnabled: true
                Behavior on anchors.topMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Item {
                    id: dockHoverRegion
                    anchors.fill: parent
                    implicitWidth: dockBackground.implicitWidth
                    Item { // Wrapper for the dock background
                        id: dockBackground
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            horizontalCenter: parent.horizontalCenter
                        }
                        implicitWidth: dockRow.implicitWidth + 5 * 2
                        height: parent.height - Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut
                        StyledRectangularShadow {
                            target: dockVisualBackground
                        }
                        Rectangle { // The real rectangle that is visible
                            id: dockVisualBackground
                            property real margin: Appearance.sizes.elevationMargin
                            anchors.fill: parent
                            anchors.topMargin: Appearance.sizes.elevationMargin
                            anchors.bottomMargin: Appearance.sizes.hyprlandGapsOut
                            color: Appearance.m3colors.m3surfaceContainer
                            radius: Appearance.rounding.large
                        }
                        RowLayout {
                            id: dockRow
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 3
                            property real padding: 5
                            DockButton { // Pin (keeps the dock shown and reserves space)
                                Layout.fillHeight: true
                                implicitWidth: 34
                                topInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding + 6
                                bottomInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding + 6
                                buttonRadius: Appearance.rounding.container
                                toggled: root.pinned
                                colBackgroundToggled: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                                colBackgroundToggledHover: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.75)
                                colRippleToggled: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.65)
                                onClicked: root.pinned = !root.pinned
                                contentItem: MaterialSymbol {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "keep"
                                    fill: root.pinned ? 1 : 0
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: root.pinned ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                                }
                            }
                            DockSeparator {}
                            DockApps {
                                id: dockApps
                                buttonPadding: dockRow.padding
                            }
                            DockSeparator {}
                            DockButton { // App launcher: a tinted round badge
                                Layout.fillHeight: true
                                onClicked: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                                topInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding
                                bottomInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding
                                buttonRadius: Appearance.rounding.normal
                                colBackground: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.72)
                                colRipple: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
                                contentItem: MaterialSymbol {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    iconSize: 24
                                    text: "apps"
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
