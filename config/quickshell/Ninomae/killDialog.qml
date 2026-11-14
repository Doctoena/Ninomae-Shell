//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Opened by services/ConflictKiller.qml when a program that takes the tray or notifications from the shell is
 * running: NINOMAE_CONFLICTS names which ("trays,notifications"). One joined row each (Keep / Stop) and a switch
 * to stop them every time. Closes when nothing is left to answer.
 *   NINOMAE_CONFLICTS=trays,notifications qs -p killDialog.qml   (to see it)
 */
ApplicationWindow {
    id: root
    title: Translation.tr("Shell conflicts")
    visible: conflicts.length > 0
    onClosing: Qt.quit()
    color: Appearance.colors.colLayer0

    readonly property list<string> conflicts: (Quickshell.env("NINOMAE_CONFLICTS") ?? "").split(",").filter(c => c)
    property int answered: 0
    property bool always: false
    onAnsweredChanged: if (answered >= conflicts.length) Qt.quit()

    readonly property int padding: 16
    readonly property real fitHeight: content.implicitHeight + padding * 2
    width: 460
    height: fitHeight
    minimumWidth: 460
    maximumWidth: 460
    minimumHeight: fitHeight
    maximumHeight: fitHeight

    Component.onCompleted: {
        Config.readWriteDelay = 0; // One option at a time
        MaterialThemeLoader.reapplyTheme();
        if (conflicts.length === 0) Qt.callLater(Qt.quit); // Nothing to ask (quitting while loading is ignored)
    }

    component Conflict: SettingRow {
        id: row
        required property string kind // In NINOMAE_CONFLICTS
        required property list<string> programs
        required property string option // Config.options.conflictKiller.<option>: stop them every time
        property bool done: false
        visible: root.conflicts.includes(kind) && !done
        function answer() { done = true; root.answered++; }
        DialogButton {
            buttonText: Translation.tr("Keep")
            onClicked: row.answer()
        }
        DialogButton {
            primary: true
            buttonText: Translation.tr("Stop")
            onClicked: {
                Quickshell.execDetached(["killall", ...row.programs]);
                if (root.always) Config.options.conflictKiller[row.option] = true;
                row.answer();
            }
        }
    }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.padding }
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 12
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: Translation.tr("Programs in the way")
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.Black
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("They do a job the shell already does.")
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
            }
            RippleButton {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.segment
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: root.close()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "close"
                    iconSize: 20
                }
            }
        }

        Conflict {
            text: Translation.tr("KDE services")
            description: Translation.tr("Takes over the system tray")
            kind: "trays"
            programs: ["kded6"]
            option: "autoKillTrays"
        }
        Conflict {
            text: Translation.tr("Another notification app")
            description: Translation.tr("Shows its own notifications (mako, dunst)")
            kind: "notifications"
            programs: ["mako", "dunst"]
            option: "autoKillNotificationDaemons"
        }
        SettingRow {
            text: Translation.tr("Stop them every time the shell starts")
            description: Translation.tr("Can be turned off in Settings → Advanced")
            StyledSwitch {
                checked: root.always
                onClicked: root.always = checked
            }
        }
    }
}
