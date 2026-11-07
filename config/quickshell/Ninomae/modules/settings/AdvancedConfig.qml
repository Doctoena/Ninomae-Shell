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
        title: Translation.tr("Search")
        spacing: 10
        ConfigSwitch {
            text: Translation.tr("Always offer to run, calculate and search the web")
            option: "search.prefix.showDefaultActionsWithoutPrefix"
            tooltip: Translation.tr("At the end of the results, without typing their prefix")
        }
        ConfigSwitch {
            text: Translation.tr("Forgiving matching")
            option: "search.sloppy"
            tooltip: Translation.tr("Finds results even with typos, but ranks them less tidily")
        }
        ConfigSpinBox {
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
            PrefixRow { key: "app"; name: Translation.tr("Apps"); description: Translation.tr("Only apps") }
            PrefixRow { key: "action"; name: Translation.tr("Actions"); description: Translation.tr("Commands such as /dark or /light") }
            PrefixRow { key: "clipboard"; name: Translation.tr("Clipboard"); description: Translation.tr("What you copied lately") }
            PrefixRow { key: "emojis"; name: Translation.tr("Emoji"); description: Translation.tr("Find an emoji by name") }
            PrefixRow { key: "math"; name: Translation.tr("Calculator"); description: Translation.tr("Work something out") }
            PrefixRow { key: "shellCommand"; name: Translation.tr("Run a command"); description: Translation.tr("Run what you type in a shell") }
            PrefixRow { key: "webSearch"; name: Translation.tr("Web search"); description: Translation.tr("Search the web for what you type") }
        }
    }
    ContentSection {
        title: Translation.tr("Screenshots")
        spacing: 10
        ConfigSwitch {
            text: Translation.tr("Also save them to a folder")
            option: "regionSelector.save"
            tooltip: Translation.tr("They're always copied to the clipboard")
        }
        SettingRow {
            visible: Config.options.regionSelector.save
            text: Translation.tr("Folder")
            description: Translation.tr("Where screenshots are saved")
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
        title: Translation.tr("Expert")
        spacing: 10
        ConfigSwitch {
            text: Translation.tr("Stop other notification daemons")
            option: "conflictKiller.autoKillNotificationDaemons"
            tooltip: Translation.tr("Only one app can show notifications, so others (dunst, mako…) are closed")
        }
        ConfigSwitch {
            text: Translation.tr("Stop other system trays")
            option: "conflictKiller.autoKillTrays"
            tooltip: Translation.tr("Other tray apps would take the tray icons away from the bar")
        }
        SettingRow {
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
