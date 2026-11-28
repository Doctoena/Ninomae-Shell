import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
Loader {
    id: root
    property color color: Appearance.colors.colOnSurfaceVariant
    active: HyprlandXkb.layoutCodes.length > 1
    visible: active
    // "us:dvorak" → "us\ndvor": each part cut to four letters, one per line
    function abbreviateLayoutCode(fullCode) {
        return fullCode.split(':').map(layout => layout.split('-')[0].slice(0, 4)).join('\n');
    }
    sourceComponent: Item {
        implicitWidth: layoutCodeText.implicitWidth
        StyledText {
            id: layoutCodeText
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: abbreviateLayoutCode(HyprlandXkb.currentLayoutCode)
            font.pixelSize: text.includes("\n") ? Appearance.font.pixelSize.smallie : Appearance.font.pixelSize.small
            color: root.color
            animateChange: true
        }
    }
}
