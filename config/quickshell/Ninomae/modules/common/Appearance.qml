import QtQuick
import Quickshell
import qs.modules.common.functions
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Appearance singleton - centralized theming, colors, animations, and sizes.
 */
Singleton {
    id: root

    property QtObject m3colors
    property bool colorFade: false // True only during a theme transition
    property QtObject animation
    property QtObject animationCurves
    property QtObject colors
    property QtObject rounding
    property QtObject font
    property QtObject sizes
    property string syntaxHighlightingTheme

    m3colors: QtObject {
        property bool darkmode: true
        property bool transparent: false
        property color m3background: "#141313"
        property color m3onBackground: "#e6e1e1"
        property color m3surface: "#141313"
        property color m3surfaceDim: "#141313"
        property color m3surfaceBright: "#3a3939"
        property color m3surfaceContainerLowest: "#0f0e0e"
        property color m3surfaceContainerLow: "#1c1b1c"
        property color m3surfaceContainer: "#201f20"
        property color m3surfaceContainerHigh: "#2b2a2a"
        property color m3surfaceContainerHighest: "#363435"
        property color m3onSurface: "#e6e1e1"
        property color m3surfaceVariant: "#49464a"
        property color m3onSurfaceVariant: "#cbc5ca"
        property color m3inverseSurface: "#e6e1e1"
        property color m3inverseOnSurface: "#313030"
        property color m3outline: "#948f94"
        property color m3outlineVariant: "#49464a"
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        property color m3surfaceTint: "#cbc4cb"
        property color m3primary: "#cbc4cb"
        property color m3onPrimary: "#322f34"
        property color m3primaryContainer: "#2d2a2f"
        property color m3onPrimaryContainer: "#bcb6bc"
        property color m3inversePrimary: "#615d63"
        property color m3secondary: "#cac5c8"
        property color m3onSecondary: "#323032"
        property color m3secondaryContainer: "#4d4b4d"
        property color m3onSecondaryContainer: "#ece6e9"
        property color m3tertiary: "#d1c3c6"
        property color m3onTertiary: "#372e30"
        property color m3tertiaryContainer: "#31292b"
        property color m3onTertiaryContainer: "#c1b4b7"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
        property color m3errorContainer: "#93000a"
        property color m3onErrorContainer: "#ffdad6"
        property color m3primaryFixed: "#e7e0e7"
        property color m3primaryFixedDim: "#cbc4cb"
        property color m3onPrimaryFixed: "#1d1b1f"
        property color m3onPrimaryFixedVariant: "#49454b"
        property color m3secondaryFixed: "#e6e1e4"
        property color m3secondaryFixedDim: "#cac5c8"
        property color m3onSecondaryFixed: "#1d1b1d"
        property color m3onSecondaryFixedVariant: "#484648"
        property color m3tertiaryFixed: "#eddfe1"
        property color m3tertiaryFixedDim: "#d1c3c6"
        property color m3onTertiaryFixed: "#211a1c"
        property color m3onTertiaryFixedVariant: "#4e4447"
        property color m3success: "#B5CCBA"
        property color m3onSuccess: "#213528"
        property color m3successContainer: "#374B3E"
        property color m3onSuccessContainer: "#D1E9D6"
        property color term0: "#EDE4E4"
        property color term1: "#B52755"
        property color term2: "#A97363"
        property color term3: "#AF535D"
        property color term4: "#A67F7C"
        property color term5: "#B2416B"
        property color term6: "#8D76AD"
        property color term7: "#272022"
        property color term8: "#0E0D0D"
        property color term9: "#B52755"
        property color term10: "#A97363"
        property color term11: "#AF535D"
        property color term12: "#A67F7C"
        property color term13: "#B2416B"
        property color term14: "#8D76AD"
        property color term15: "#221A1A"

        // Theme changes fade instead of snapping (switched on by modules/themeTransition)
        Behavior on m3background { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onBackground { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3surface { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3surfaceDim { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3surfaceBright { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3surfaceContainerLowest { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3surfaceContainerLow { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3surfaceContainer { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3surfaceContainerHigh { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3surfaceContainerHighest { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onSurface { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3surfaceVariant { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onSurfaceVariant { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3inverseSurface { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3inverseOnSurface { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3outline { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3outlineVariant { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3shadow { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3scrim { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3surfaceTint { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3primary { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onPrimary { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3primaryContainer { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onPrimaryContainer { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3inversePrimary { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3secondary { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onSecondary { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3secondaryContainer { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onSecondaryContainer { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3tertiary { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onTertiary { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3tertiaryContainer { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onTertiaryContainer { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3error { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onError { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3errorContainer { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onErrorContainer { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3primaryFixed { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3primaryFixedDim { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onPrimaryFixed { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onPrimaryFixedVariant { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3secondaryFixed { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3secondaryFixedDim { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onSecondaryFixed { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onSecondaryFixedVariant { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3tertiaryFixed { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3tertiaryFixedDim { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onTertiaryFixed { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onTertiaryFixedVariant { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3success { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onSuccess { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3successContainer { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
        Behavior on m3onSuccessContainer { enabled: root.colorFade; ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
    }
    colors: QtObject {
        property color colSubtext: m3colors.m3outline
        property color colLayer0: ColorUtils.mix(m3colors.m3background, m3colors.m3primary, Config.options.appearance.extraBackgroundTint ? 0.99 : 1)
        property color colOnLayer0: m3colors.m3onBackground
        property color colLayer0Hover: ColorUtils.mix(colLayer0, colOnLayer0, 0.9)
        property color colLayer0Active: ColorUtils.mix(colLayer0, colOnLayer0, 0.8)
        property color colLayer0Border: ColorUtils.mix(root.m3colors.m3outlineVariant, colLayer0, 0.4)
        property color colLayer1: m3colors.m3surfaceContainerLow;
        property color colOnLayer1: m3colors.m3onSurfaceVariant;
        property color colOnLayer1Inactive: ColorUtils.mix(colOnLayer1, colLayer1, 0.45);
        property color colLayer2: m3colors.m3surfaceContainer
        property color colOnLayer2: m3colors.m3onSurface;
        property color colLayer1Hover: ColorUtils.mix(colLayer1, colOnLayer1, 0.92)
        property color colLayer1Active: ColorUtils.mix(colLayer1, colOnLayer1, 0.85);
        property color colLayer2Hover: ColorUtils.mix(colLayer2, colOnLayer2, 0.90)
        property color colLayer2Active: ColorUtils.mix(colLayer2, colOnLayer2, 0.80);
        property color colLayer3: m3colors.m3surfaceContainerHigh
        property color colOnLayer3: m3colors.m3onSurface;
        property color colLayer3Hover: ColorUtils.mix(colLayer3, colOnLayer3, 0.90)
        property color colLayer3Active: ColorUtils.mix(colLayer3, colOnLayer3, 0.80);
        property color colLayer4: m3colors.m3surfaceContainerHighest
        property color colOnLayer4: m3colors.m3onSurface;
        property color colLayer4Hover: ColorUtils.mix(colLayer4, colOnLayer4, 0.90)
        property color colLayer4Active: ColorUtils.mix(colLayer4, colOnLayer4, 0.80);
        property color colPrimary: m3colors.m3primary
        property color colOnPrimary: m3colors.m3onPrimary
        property color colPrimaryHover: ColorUtils.mix(colors.colPrimary, colLayer1Hover, 0.87)
        property color colPrimaryActive: ColorUtils.mix(colors.colPrimary, colLayer1Active, 0.7)
        property color colPrimaryContainer: m3colors.m3primaryContainer
        property color colOnPrimaryContainer: m3colors.m3onPrimaryContainer
        property color colSecondary: m3colors.m3secondary
        property color colSecondaryContainer: m3colors.m3secondaryContainer
        property color colSecondaryContainerHover: ColorUtils.mix(m3colors.m3secondaryContainer, m3colors.m3onSecondaryContainer, 0.90)
        property color colSecondaryContainerActive: ColorUtils.mix(m3colors.m3secondaryContainer, m3colors.m3onSecondaryContainer, 0.54)
        property color colTertiary: m3colors.m3tertiary
        property color colOnSecondaryContainer: m3colors.m3onSecondaryContainer
        property color colSurfaceContainerLow: m3colors.m3surfaceContainerLow
        property color colSurfaceContainer: m3colors.m3surfaceContainer
        property color colSurfaceContainerHigh: m3colors.m3surfaceContainerHigh
        property color colSurfaceContainerHighest: m3colors.m3surfaceContainerHighest
        property color colSurfaceContainerHighestHover: ColorUtils.mix(m3colors.m3surfaceContainerHighest, m3colors.m3onSurface, 0.95)
        property color colOnSurface: m3colors.m3onSurface
        property color colOnSurfaceVariant: m3colors.m3onSurfaceVariant
        // Dark surface like the rest of the shell (Material's inverse surface comes out near-white in dark mode)
        property color colTooltip: colSurfaceContainerHigh
        property color colOnTooltip: colOnSurface
        property color colScrim: ColorUtils.transparentize(m3colors.m3scrim, 0.5)
        property color colShadow: ColorUtils.transparentize(m3colors.m3shadow, 0.7)
        property color colOutline: m3colors.m3outline
        property color colOutlineVariant: m3colors.m3outlineVariant
        property color colError: m3colors.m3error
        property color colOnError: m3colors.m3onError
        property color colErrorContainer: m3colors.m3errorContainer
        property color colOnErrorContainer: m3colors.m3onErrorContainer
    }
    rounding: QtObject {
        property int unsharpen: 2
        property int unsharpenmore: 6
        property int verysmall: 8
        property int small: 12
        property int normal: 17
        property int large: 23
        property int verylarge: 30
        property int full: 9999
        // Squircle language: corner radius by control height
        property int chip: 8 // 24 px chips
        property int segment: 10 // 30 px segments and icon buttons
        property int container: 12 // 36 px containers
        property int screenRounding: large
        property int windowRounding: 18
    }
    font: QtObject {
        property QtObject family: QtObject {
            property string main: "Roboto Flex"
            property string numbers: "Rubik"
            property string title: "Gabarito"
            property string iconMaterial: "Material Symbols Rounded"
            property string iconNerd: "JetBrains Mono NF"
            property string monospace: "JetBrains Mono NF"
            property string expressive: "Space Grotesk"
        }
        property QtObject variableAxes: QtObject {
            // Roboto Flex is customized to feel geometric, unserious yet not overly kiddy
            property var main: ({
                "YTUC": 716, // Uppercase height (Raised from 712 to be more distinguishable from lowercase)
                "YTFI": 716, // Figure (numbers) height (Lowered from 738 to match uppercase)
                "YTAS": 716, // Ascender height (Lowered from 750 to match uppercase)
                "YTLC": 490, // Lowercase height (Lowered from 514 to be more distinguishable from uppercase)
                "XTRA": 488, // Counter width (Raised from 468 to be less condensed, less serious)
                "wdth": 105, // Width (Space out a tiny bit for readability)
                "GRAD": 175, // Grade (Increased so the 6 and 9 don't look weak)
                "wght": 300, // Weight (Lowered to compensate for increased grade)
            })
            // Rubik simply needs regular weight to override that of the main font where necessary
            property var numbers: ({
                "wght": 400,
            })
            // Slightly bold weight for title
            property var title: ({
                "wght": 900,
            })
        }
        property QtObject pixelSize: QtObject {
            property int smallest: 10
            property int smaller: 12
            property int smallie: 13
            property int small: 15
            property int normal: 16
            property int large: 17
            property int larger: 19
            property int huge: 22
            property int hugeass: 30
            property int title: huge
        }
    }
    animationCurves: QtObject {
        readonly property list<real> expressiveFastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1] // Default, 350ms
        readonly property list<real> expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1] // Default, 500ms
        readonly property list<real> expressiveEffects: [0.34, 0.80, 0.34, 1.00, 1, 1] // Default, 200ms
        readonly property list<real> emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property list<real> emphasizedFirstHalf: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82]
        readonly property list<real> emphasizedLastHalf: [5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property list<real> emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]
        readonly property list<real> emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
        readonly property list<real> standard: [0.2, 0, 0, 1, 1, 1]
        readonly property list<real> standardDecel: [0, 0, 0, 1, 1, 1]
        // Gooey drawers (launcher, popups, sidebar, OSD, power menu...). Open glides out evenly and
        // settles with a slight (3%) overshoot; close starts at once and eases into the bar.
        // (Was [0.12, 0.9, 0.22, 1.08] over 330 ms: 90% of the travel in the first third, then a crawl
        // and an 8% wobble, which read as a jolt rather than a glide.)
        readonly property list<real> drawerOpen: [0.22, 0.85, 0.32, 1.03, 1, 1]
        readonly property list<real> drawerClose: [0.3, 0.3, 0.2, 1, 1, 1]
        readonly property real drawerOpenDuration: 360
        readonly property real drawerCloseDuration: 220
        readonly property real drawerLargeExtra: 40 // Added for the big drawers (sidebar, game launcher)
        readonly property real expressiveFastSpatialDuration: 350
        readonly property real expressiveDefaultSpatialDuration: 500
        readonly property real expressiveEffectsDuration: 200
    }
    animation: QtObject {
        property QtObject elementMove: QtObject {
            property int duration: animationCurves.expressiveDefaultSpatialDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveDefaultSpatial
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMove.duration
                    easing.type: root.animation.elementMove.type
                    easing.bezierCurve: root.animation.elementMove.bezierCurve
                }
            }
        }
        property QtObject elementMoveEnter: QtObject {
            property int duration: 400
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedDecel
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMoveEnter.duration
                    easing.type: root.animation.elementMoveEnter.type
                    easing.bezierCurve: root.animation.elementMoveEnter.bezierCurve
                }
            }
        }
        property QtObject elementMoveExit: QtObject {
            property int duration: 200
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedAccel
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMoveExit.duration
                    easing.type: root.animation.elementMoveExit.type
                    easing.bezierCurve: root.animation.elementMoveExit.bezierCurve
                }
            }
        }
        property QtObject elementMoveFast: QtObject {
            property int duration: animationCurves.expressiveEffectsDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveEffects
            property int velocity: 850
            property Component colorAnimation: Component { ColorAnimation {
                duration: root.animation.elementMoveFast.duration
                easing.type: root.animation.elementMoveFast.type
                easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
            }}
            property Component numberAnimation: Component { NumberAnimation {
                    duration: root.animation.elementMoveFast.duration
                    easing.type: root.animation.elementMoveFast.type
                    easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
            }}
        }
        property QtObject elementResize: QtObject {
            property int duration: 300
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasized
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementResize.duration
                    easing.type: root.animation.elementResize.type
                    easing.bezierCurve: root.animation.elementResize.bezierCurve
                }
            }
        }
        property QtObject clickBounce: QtObject {
            property int duration: 400
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveDefaultSpatial
            property int velocity: 850
            property Component numberAnimation: Component { NumberAnimation {
                    duration: root.animation.clickBounce.duration
                    easing.type: root.animation.clickBounce.type
                    easing.bezierCurve: root.animation.clickBounce.bezierCurve
            }}
        }
        property QtObject scroll: QtObject {
            property int duration: 200
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.standardDecel
        }
    }
    sizes: QtObject {
        property real baseBarHeight: 40
        property real barHeight: Config.options.bar.cornerStyle === 1 ?
            (baseBarHeight + root.sizes.hyprlandGapsOut * 2) : baseBarHeight
        property real barCenterSideModuleWidth: Config.options?.bar.verbose ? 360 : 140
        property real barCenterSideModuleWidthShortened: 280
        property real barCenterSideModuleWidthHellaShortened: 190
        property real barShortenScreenWidthThreshold: 1200 // Shorten if screen width is at most this value
        property real barHellaShortenScreenWidthThreshold: 1000 // Shorten even more...
        property real elevationMargin: 10
        property real hyprlandGapsOut: 5
        property real mediaControlsWidth: 440
        property real notificationPopupWidth: 410
        property real osdWidth: 180
        property real sidebarWidth: 460
        property real baseVerticalBarWidth: 46
        property real verticalBarWidth: Config.options.bar.cornerStyle === 1 ?
            (baseVerticalBarWidth + root.sizes.hyprlandGapsOut * 2) : baseVerticalBarWidth
    }
    syntaxHighlightingTheme: root.m3colors.darkmode ? "Monokai" : "ayu Light"
}
