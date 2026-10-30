import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ContentPage {
    id: page
    // Read once when the page opens: versions, and what this computer is
    property var info: ({})
    Process {
        running: true
        command: ["bash", "-c", `
            echo "hyprland=$(hyprctl version -j 2>/dev/null | jq -r .version)"
            echo "quickshell=$(qs --version 2>/dev/null | grep -o 'Quickshell [0-9.]*' | cut -d' ' -f2)"
            echo "matugen=$(matugen --version 2>/dev/null | cut -d' ' -f2)"
            echo "host=$(cat /etc/hostname 2>/dev/null)"
            echo "model=$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name 2>/dev/null | paste -sd' ')"
            echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/(R)//g; s/(TM)//g; s/ CPU//; s/ @.*//; s/^ *//')"
            echo "gpu=$(lspci 2>/dev/null | grep -Ei 'vga|3d' | sed -E 's/.*\\[(.*)\\].*/\\1/' | paste -sd'|')"
            echo "memory=$(awk '/MemTotal/ { printf "%.0f GB", $2 / 1024 / 1024 }' /proc/meminfo)"
            echo "kernel=$(uname -r)"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=");
                    if (i > 0) out[line.slice(0, i)] = line.slice(i + 1).trim();
                }
                page.info = out;
            }
        }
    }

    // A fact about this computer: icon, what it is, the value
    component InfoRow: RowLayout {
        id: infoRow
        required property string icon
        required property string label
        required property string value
        visible: value !== ""
        Layout.fillWidth: true
        spacing: 12
        Rectangle {
            implicitWidth: 34
            implicitHeight: 34
            radius: Appearance.rounding.segment
            color: Appearance.m3colors.m3surfaceContainerHigh
            MaterialSymbol {
                anchors.centerIn: parent
                text: infoRow.icon
                iconSize: 18
                color: Appearance.colors.colPrimary
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                text: infoRow.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                text: infoRow.value
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
            }
        }
    }
    // A small text link
    component Link: RippleButton {
        id: link
        required property string label
        required property string url
        visible: url !== ""
        implicitHeight: 30
        horizontalPadding: 10
        buttonRadius: Appearance.rounding.segment
        colBackground: "transparent"
        colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
        onClicked: Qt.openUrlExternally(url)
        contentItem: StyledText {
            text: link.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colPrimary
        }
    }

    // ── Ninomae: the wallpaper as a banner, the name, versions and the shell's buttons ──
    ClippingRectangle {
        Layout.fillWidth: true
        implicitHeight: 190
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainer
        StyledImage {
            anchors.fill: parent
            source: Config.wallpaperPath
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 1280
            asynchronous: true
        }
        Rectangle { // Fades the wallpaper into the card on the left, so the text reads
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Appearance.m3colors.m3surfaceContainer }
                GradientStop { position: 0.45; color: Qt.alpha(Appearance.m3colors.m3surfaceContainer, 0.85) }
                GradientStop { position: 1.0; color: Qt.alpha(Appearance.m3colors.m3surfaceContainer, 0.15) }
            }
        }
        RowLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 20
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 72
                implicitHeight: 72
                radius: Appearance.rounding.large
                color: Appearance.colors.colPrimary
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "widgets"
                    iconSize: 40
                    fill: 1
                    color: Appearance.colors.colOnPrimary
                }
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                spacing: 6
                StyledText {
                    text: "Ninomae"
                    font.pixelSize: Appearance.font.pixelSize.hugeass
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    text: Translation.tr("A Quickshell desktop, coloured by your wallpaper")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 6
                    Repeater {
                        model: [
                            { icon: "desktop_windows", text: page.info.hyprland ? `Hyprland ${page.info.hyprland}` : "" },
                            { icon: "deployed_code", text: page.info.quickshell ? `Quickshell ${page.info.quickshell}` : "" },
                            { icon: "palette", text: page.info.matugen ? `matugen ${page.info.matugen}` : "" }
                        ].filter(chip => chip.text !== "")
                        delegate: InfoChip {
                            required property var modelData
                            icon: modelData.icon
                            text: modelData.text
                        }
                    }
                }
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignBottom
                spacing: 8
                RippleButtonWithIcon {
                    Layout.alignment: Qt.AlignRight
                    materialIcon: "restart_alt"
                    mainText: Translation.tr("Restart the shell")
                    onClicked: Quickshell.execDetached([`${Quickshell.env("HOME")}/.config/hypr/hyprland/scripts/restart_shell.sh`])
                    StyledToolTip {
                        text: Translation.tr("If something looks stuck. Same as Super+Ctrl+R")
                    }
                }
                RippleButtonWithIcon {
                    Layout.alignment: Qt.AlignRight
                    materialIcon: "folder_open"
                    mainText: Translation.tr("Open the dotfiles folder")
                    onClicked: Qt.openUrlExternally(`file://${Quickshell.env("HOME")}/Ninomae-Shell`)
                }
            }
        }
    }

    // ── This computer ──
    ContentSection {
        icon: "computer"
        title: Translation.tr("This computer")
        spacing: 14
        RowLayout { // The distro
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 16
            IconImage {
                implicitSize: 52
                source: SystemInfo.logo ? Quickshell.iconPath(SystemInfo.logo) : "" // Read from os-release a moment after start
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: SystemInfo.distroName
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: -10 // The links' own padding: lines them up with the name
                    spacing: 0
                    Link { label: Translation.tr("Website"); url: SystemInfo.homeUrl.replace(/^\[.*\]\((.*)\)$/, "$1") }
                    Link { label: Translation.tr("Documentation"); url: SystemInfo.documentationUrl }
                    Link { label: Translation.tr("Help"); url: SystemInfo.supportUrl }
                    Link { label: Translation.tr("Report a bug"); url: SystemInfo.bugReportUrl }
                    Link { label: Translation.tr("Privacy"); url: SystemInfo.privacyPolicyUrl }
                }
            }
        }
        GridLayout { // The hardware, in two columns
            Layout.fillWidth: true
            Layout.leftMargin: 4
            columns: width >= 700 ? 2 : 1
            columnSpacing: 24
            rowSpacing: 12
            uniformCellWidths: true
            InfoRow { icon: "laptop_chromebook"; label: Translation.tr("Device"); value: [page.info.model, page.info.host ? `(${page.info.host})` : ""].filter(x => x).join(" ") }
            InfoRow { icon: "memory"; label: Translation.tr("Processor"); value: page.info.cpu ?? "" }
            InfoRow { icon: "developer_board"; label: Translation.tr("Graphics"); value: (page.info.gpu ?? "").split("|").filter(x => x).join(" + ") }
            InfoRow { icon: "memory_alt"; label: Translation.tr("Memory"); value: page.info.memory ?? "" }
            InfoRow { icon: "terminal"; label: Translation.tr("Kernel"); value: page.info.kernel ?? "" }
            InfoRow { icon: "schedule"; label: Translation.tr("Up for"); value: DateTime.uptime }
        }
    }

    // ── Credits ──
    ContentSection {
        icon: "favorite"
        title: Translation.tr("Built on")
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 6
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("end-4's dotfiles, the starting point, with ideas from Caelestia")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
            }
            Link { label: "end-4"; url: "https://github.com/end-4/dots-hyprland" }
            Link { label: "Caelestia"; url: "https://github.com/caelestia-dots/shell" }
            Link { label: "Quickshell"; url: "https://quickshell.org" }
        }
    }
}
