import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ContentPage {
    id: page
    // A search prefix as a settings row: icon and name on the left, its character in a small box on the right
    component PrefixRow: SettingRow {
        id: row
        required property string key // In search.prefix
        required property string name
        text: name
        TextField {
            id: prefixField
            implicitWidth: 44
            implicitHeight: 32
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            maximumLength: 3
            text: Config.options.search.prefix[row.key]
            onTextEdited: Config.options.search.prefix[row.key] = text
            color: Appearance.colors.colOnLayer2
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.small
            selectionColor: Appearance.colors.colSecondaryContainer
            background: Rectangle {
                radius: Appearance.rounding.small
                color: Appearance.m3colors.m3surfaceContainerHigh
                border.width: prefixField.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary
            }
        }
    }

    ContentSection {
        icon: "search"
        title: Translation.tr("Search")
        spacing: 10
        ConfigSwitch {
            buttonIcon: "new_releases"
            text: Translation.tr("Always offer to run, calculate and search the web")
            option: "search.prefix.showDefaultActionsWithoutPrefix"
            tooltip: Translation.tr("At the end of the results, without typing their prefix")
        }
        ConfigSwitch {
            buttonIcon: "manage_search"
            text: Translation.tr("Forgiving matching")
            option: "search.sloppy"
            tooltip: Translation.tr("Finds results even with typos, but ranks them less tidily")
        }
        ConfigSpinBox {
            icon: "timer"
            text: Translation.tr("Wait before results other than apps")
            tooltip: Translation.tr("Keeps typing smooth")
            option: "search.nonAppResultDelay"
            suffix: "ms"
            from: 0
            to: 500
            stepSize: 5
        }
        ContentSubsection {
            title: Translation.tr("Prefixes")
            tooltip: Translation.tr("Start a search with one of these to search only that kind of thing")
            PrefixRow { key: "app"; name: Translation.tr("Apps"); icon: "apps" }
            PrefixRow { key: "action"; name: Translation.tr("Actions"); icon: "bolt" }
            PrefixRow { key: "clipboard"; name: Translation.tr("Clipboard"); icon: "content_paste" }
            PrefixRow { key: "emojis"; name: Translation.tr("Emoji"); icon: "mood" }
            PrefixRow { key: "math"; name: Translation.tr("Calculator"); icon: "calculate" }
            PrefixRow { key: "shellCommand"; name: Translation.tr("Run a command"); icon: "terminal" }
            PrefixRow { key: "webSearch"; name: Translation.tr("Web search"); icon: "travel_explore" }
        }
    }
    ContentSection {
        icon: "screenshot_region"
        title: Translation.tr("Screenshots")
        spacing: 10
        ConfigSwitch {
            buttonIcon: "save"
            text: Translation.tr("Also save them to a folder")
            option: "regionSelector.save"
            tooltip: Translation.tr("They're always copied to the clipboard")
        }
        SettingRow {
            visible: Config.options.regionSelector.save
            icon: "folder"
            text: Translation.tr("Folder")
            StyledTextArea {
                Layout.preferredWidth: 320
                text: Config.options.regionSelector.saveDir
                onTextChanged: Config.options.regionSelector.saveDir = text
            }
            RippleButtonWithIcon {
                materialIcon: "folder_open"
                mainText: Translation.tr("Open")
                onClicked: Qt.openUrlExternally(`file://${Config.expandHome(Config.options.regionSelector.saveDir)}`)
            }
        }
    }
    ContentSection {
        icon: "terminal"
        title: Translation.tr("Expert")
        spacing: 10
        ConfigSwitch {
            buttonIcon: "notifications_off"
            text: Translation.tr("Stop other notification daemons")
            option: "conflictKiller.autoKillNotificationDaemons"
            tooltip: Translation.tr("Only one app can show notifications, so others (dunst, mako…) are closed")
        }
        ConfigSwitch {
            buttonIcon: "shelf_auto_hide"
            text: Translation.tr("Stop other system trays")
            option: "conflictKiller.autoKillTrays"
            tooltip: Translation.tr("Other tray apps would take the tray icons away from the bar")
        }
        SettingRow {
            icon: "description"
            text: Translation.tr("Shell config file")
            tooltip: Translation.tr("Every option, including ones not shown here")
            RippleButtonWithIcon {
                materialIcon: "content_copy"
                mainText: Translation.tr("Copy path")
                onClicked: Quickshell.clipboardText = Directories.shellConfigPath
            }
            RippleButtonWithIcon {
                materialIcon: "edit"
                mainText: Translation.tr("Open")
                onClicked: Qt.openUrlExternally(Directories.shellConfigPath)
            }
        }
    }
}
